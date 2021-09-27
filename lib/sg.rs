use std::future::Future;
use std::sync::Arc;

use ::reqwest::Client;
use anyhow::Context;
use anyhow::Result;
use graphql_client::reqwest::post_graphql;
use graphql_client::GraphQLQuery;
use mlua::prelude::*;
use mlua::UserData;
use regex::Regex;
use serde;

#[derive(serde::Serialize, serde::Deserialize, Clone)]
pub struct RemoteFile {
  pub remote: String,
  pub commit: String,
  pub path: String,
  pub line: Option<usize>,
  pub col: Option<usize>,
}

impl UserData for RemoteFile {
  fn add_methods<'lua, M: mlua::UserDataMethods<'lua, Self>>(methods: &mut M) {
    let r = Arc::new(tokio::runtime::Runtime::new().unwrap());

    methods.add_method("bufname", |lua, t, ()| t.bufname().to_lua(lua));

    let read_runtime = r.clone();
    methods.add_method("read", move |_, remote_file, ()| {
      // TODO: There has to be a cleaner way to write this
      match read_runtime.block_on(remote_file.read()) {
        Ok(val) => Ok(val),
        Err(err) => return Err(err.to_lua_err()),
      }
    });
  }

  fn add_fields<'lua, F: mlua::UserDataFields<'lua, Self>>(fields: &mut F) {
    fields.add_field_method_get("remote", |lua, t| t.remote.to_string().to_lua(lua));
    fields.add_field_method_get("commit", |lua, t| t.commit.to_string().to_lua(lua));
    fields.add_field_method_get("path", |lua, t| t.path.to_string().to_lua(lua));

    fields.add_field_method_get("line", |lua, t| match t.line {
      Some(line) => line.to_lua(lua),
      None => Ok(LuaNil),
    });
    fields.add_field_method_get("col", |lua, t| match t.col {
      Some(col) => col.to_lua(lua),
      None => Ok(LuaNil),
    });
  }
}

#[derive(GraphQLQuery)]
#[graphql(
  schema_path = "gql/schema.graphql",
  query_path = "gql/file_query.graphql",
  response_derives = "Debug"
)]
pub struct FileQuery;

#[derive(GraphQLQuery)]
#[graphql(
  schema_path = "gql/schema.graphql",
  query_path = "gql/commit_query.graphql",
  response_derives = "Debug"
)]
pub struct CommitQuery;

// TODO: Memoize... :)
//  Noah says learn about:
//      inner mutability
//      refcells
pub async fn get_commit_hash(remote: String, revision: String) -> Result<String> {
  // TODO: Could probably make sure that there are not "/" etc.
  if revision.len() == 40 {
    return Ok(revision.to_owned());
  }

  // TODO: How expensive is this?
  let sourcegraph_access_token = std::env::var("SRC_ACCESS_TOKEN").expect("Sourcegraph access token");
  let client = Client::builder()
    .default_headers(
      std::iter::once((
        reqwest::header::AUTHORIZATION,
        reqwest::header::HeaderValue::from_str(&format!("Bearer {}", sourcegraph_access_token)).unwrap(),
      ))
      .collect(),
    )
    .build()?;

  let response_body = post_graphql::<CommitQuery, _>(
    &client,
    "https://sourcegraph.com/.api/graphql",
    commit_query::Variables {
      name: remote.to_string(),
      rev: revision.to_string(),
    },
  )
  .await?;

  Ok(
    response_body
      .data
      .context("No data")?
      .repository
      .context("No matching repository found")?
      .commit
      .context("No matching commit found")?
      .oid,
  )
}

pub async fn get_remote_file_contents(remote: &str, commit: &str, path: &str) -> Result<Vec<String>> {
  let sourcegraph_access_token = std::env::var("SRC_ACCESS_TOKEN").expect("Sourcegraph access token");
  let client = Client::builder()
    .default_headers(
      std::iter::once((
        reqwest::header::AUTHORIZATION,
        reqwest::header::HeaderValue::from_str(&format!("Bearer {}", sourcegraph_access_token)).unwrap(),
      ))
      .collect(),
    )
    .build()?;

  let response_body = post_graphql::<FileQuery, _>(
    &client,
    "https://sourcegraph.com/.api/graphql",
    file_query::Variables {
      name: remote.to_string(),
      rev: commit.to_string(),
      path: path.to_string(),
    },
  )
  .await?;

  Ok(
    response_body
      .data
      .context("No data")?
      .repository
      .context("No matching repository found")?
      .commit
      .context("No matching commit found")?
      .file
      .context("No matching File")?
      .content
      .split("\n")
      .map(|x| x.to_string())
      .collect(),
  )
}

impl RemoteFile {
  fn shortened_remote(&self) -> String {
    if self.remote == "github.com" {
      "gh".to_string()
    } else {
      self.remote.to_owned()
    }
  }

  fn shortened_commit(&self) -> String {
    self.commit[..5].to_string()
  }

  pub fn bufname(&self) -> String {
    format!(
      "sg://{}{}/-/{}",
      self.shortened_remote(),
      self.shortened_commit(),
      self.path
    )
  }

  pub fn sourcegraph_url(&self) -> String {
    format!(
      "https://sourcegraph.com/{}@{}/-/blob/{}",
      self.remote, self.commit, self.path
    )
  }

  pub async fn read(&self) -> Result<Vec<String>> {
    get_remote_file_contents(&self.remote, &self.commit, &self.path).await
  }

  // pub fn read_sync(&self) -> Result<String> {
  // }
}

fn normalize_url(url: &str) -> String {
  // TODO: This is a bit ugly atm
  url
    .clone()
    .to_string()
    .replace("//gh/", "//github.com/")
    .replace("https://sourcegraph.com/", "")
    .replace("sg://", "")
}

// async fn return_raw_commit(_remote: &str, commit: &str) -> Result<String> {
//   Ok(commit.to_string())
// }

pub async fn uri_from_link<Fut>(url: &str, converter: fn(String, String) -> Fut) -> Result<RemoteFile>
where
  Fut: Future<Output = Result<String>>,
{
  let url = normalize_url(url);

  let split: Vec<&str> = url.split("/-/").collect();
  if split.len() != 2 {
    return Err(anyhow::anyhow!("Expected url to be split by /-/"));
  }

  let remote_with_commit = split[0].to_string();
  let mut split_remote: Vec<&str> = remote_with_commit.split("@").collect();
  let remote = split_remote.remove(0).to_string();
  let commit = converter(
    remote.clone(),
    if split_remote.is_empty() {
      "HEAD".to_string()
    } else {
      split_remote.remove(0).to_string()
    },
  )
  .await?;

  let prefix_regex = Regex::new("^(blob|tree)/")?;
  let replaced_path = prefix_regex.replace(split[1], "");
  let path_and_args: Vec<&str> = replaced_path.split("?").collect();

  if path_and_args.len() > 2 {
    return Err(anyhow::anyhow!("Too many question marks. Please don't do that"));
  }

  let path = path_and_args[0].to_string();
  let (line, col) = if path_and_args.len() == 2 {
    // TODO: We could probably handle a few more cases here :)
    let arg_split: Vec<&str> = path_and_args[1].split(":").collect();

    if arg_split.len() != 2 {
      (None, None)
    } else {
      (
        Some(arg_split[0][1..].parse().unwrap_or(1)),
        Some(arg_split[1].parse().unwrap_or(1)),
      )
    }
  } else {
    (None, None)
  };

  Ok(RemoteFile {
    remote,
    commit,
    path,
    line,
    col,
  })
}

// #[cfg(test)]
// mod test {
//   use super::*;

//   async fn return_raw_commit(_remote: &str, commit: &str) -> Result<String> {
//     Ok(commit.to_string())
//   }

//   #[tokio::test]
//   async fn create() -> Result<()> {
//     let test_cases = vec![
//       "https://sourcegraph.com/github.com/neovim/neovim/-/blob/src/nvim/autocmd.c",
//       "https://sourcegraph.com/github.com/neovim/neovim/-/tree/src/nvim/autocmd.c",
//       "sg://github.com/neovim/neovim/-/blob/src/nvim/autocmd.c",
//       "sg://github.com/neovim/neovim/-/tree/src/nvim/autocmd.c",
//       "sg://gh/neovim/neovim/-/blob/src/nvim/autocmd.c",
//       "sg://gh/neovim/neovim/-/tree/src/nvim/autocmd.c",
//       "sg://github.com/neovim/neovim/-/src/nvim/autocmd.c",
//       "sg://gh/neovim/neovim/-/src/nvim/autocmd.c",
//     ];

//     for tc in test_cases {
//       let x = uri_from_link(tc, return_raw_commit).await?;

//       assert_eq!(x.remote, "github.com/neovim/neovim");
//       assert_eq!(x.commit, "HEAD");
//       assert_eq!(x.path, "src/nvim/autocmd.c");
//       assert_eq!(x.line, None);
//       assert_eq!(x.col, None);
//     }

//     Ok(())
//   }

//   #[tokio::test]
//   async fn can_get_lines_and_columns() -> Result<()> {
//     let test_case = "sg://github.com/sourcegraph/sourcegraph@main/-/blob/dev/sg/rfc.go?L29:2".to_string();

//     let remote_file = uri_from_link(&test_case, return_raw_commit).await?;
//     assert_eq!(remote_file.remote, "github.com/sourcegraph/sourcegraph");
//     assert_eq!(remote_file.path, "dev/sg/rfc.go");
//     assert_eq!(remote_file.line, Some(29));
//     assert_eq!(remote_file.col, Some(2));

//     Ok(())
//   }
// }
