use {
    anyhow::Result, graphql_client::GraphQLQuery, lsp_types::Location, once_cell::sync::Lazy,
    regex::Regex, reqwest::Client, sg_gql::dotcom_user::UserInfo, sg_types::*,
};

pub mod auth;
pub mod entry;
pub mod nvim;

pub fn normalize_url(url: &str) -> String {
    let re = Regex::new(r"^/").unwrap();

    re.replace_all(
        &url.to_string()
            .replace(&auth::get_endpoint(), "")
            .replace("//gh/", "//github.com/")
            .replace("sg://", ""),
        "",
    )
    .to_string()
}

mod graphql {
    use {super::*, futures::Future, reqwest::header::HeaderMap};

    static CLIENT: Lazy<Client> = Lazy::new(|| {
        Client::builder()
            .build()
            .expect("to be able to create the client")
    });

    fn get_graphql_endpoint() -> String {
        let endpoint = auth::get_endpoint();
        format!("{endpoint}/.api/graphql")
    }

    pub async fn request_wrap<Q: GraphQLQuery, F, T, R>(
        variables: impl Into<Q::Variables>,
        get: F,
    ) -> Result<T>
    where
        F: Fn(&'static Client, HeaderMap, String, Q::Variables) -> R,
        R: Future<Output = Result<T>>,
        T: Sized,
    {
        let headers = get_headers();
        get(&CLIENT, headers, get_graphql_endpoint(), variables.into()).await
    }
}

pub fn get_headers() -> reqwest::header::HeaderMap {
    use reqwest::header::*;

    let mut x = HeaderMap::new();
    if let Some(sourcegraph_access_token) = auth::get_access_token() {
        x.insert(
            AUTHORIZATION,
            HeaderValue::from_str(&format!("token {sourcegraph_access_token}"))
                .expect("to make header"),
        );
    }

    x
}

macro_rules! wrap_request {
    ($path:path, $variables: expr) => {{
        use $path::*;
        graphql::request_wrap::<Query, _, _, _>($variables, request).await
    }};
}

pub async fn get_path_info(remote: String, revision: String, path: String) -> Result<PathInfo> {
    // Get rid of double slashes, since that messes up Sourcegraph API
    let remote = remote.replace("//", "/");

    wrap_request!(
        sg_gql::path_info,
        Variables {
            name: remote,
            revision,
            path
        }
    )
}

pub async fn get_remote_directory_contents(
    remote: &str,
    commit: &str,
    path: &str,
) -> Result<Vec<PathInfo>> {
    wrap_request!(
        sg_gql::list_files,
        Variables {
            name: remote.to_string(),
            rev: commit.to_string(),
            path: path.to_string()
        }
    )
}

pub async fn get_commit_hash(remote: String, revision: String) -> Result<String> {
    if revision.len() == 40 {
        return Ok(revision);
    }

    wrap_request!(
        sg_gql::commit_oid,
        Variables {
            name: remote,
            rev: revision
        }
    )
}

pub async fn get_file_contents(remote: &str, commit: &str, path: &str) -> Result<String> {
    wrap_request!(
        sg_gql::file,
        Variables {
            name: remote.to_string(),
            rev: commit.to_string(),
            path: path.to_string(),
        }
    )
}

pub async fn get_sourcegraph_version() -> Result<SourcegraphVersion> {
    auth::get_access_token().ok_or(anyhow::anyhow!("No user token. Login first"))?;

    wrap_request!(sg_gql::sourcegraph_version, Variables {})
}

pub async fn get_embeddings_context(
    repo: ID,
    query: String,
    code: i64,
    text: i64,
) -> Result<Vec<Embedding>> {
    wrap_request!(
        sg_gql::embeddings_context,
        Variables {
            repo,
            query,
            code,
            text,
        }
    )
}

pub async fn get_hover(uri: String, line: i64, character: i64) -> Result<String> {
    let remote_file = entry::Entry::new(&uri).await?;
    let remote_file = match remote_file {
        entry::Entry::File(file) => file,
        _ => return Err(anyhow::anyhow!("Can only get references of a file")),
    };

    wrap_request!(
        sg_gql::hover,
        Variables {
            repository: remote_file.remote.0,
            revision: remote_file.oid.0,
            path: remote_file.path,
            line,
            character,
        }
    )
}

pub async fn get_cody_completions(
    text: String,
    prefix: Option<String>,
    temperature: Option<f64>,
) -> Result<String> {
    // TODO: Figure out how to deal with messages

    let messages = vec![
            CodyMessage {
                speaker: CodySpeaker::Assistant,
                text: "I am Cody, an AI-powered coding assistant developed by Sourcegraph. I operate inside a Language Server Protocol implementation. My task is to help programmers with programming tasks in the %s programming language.
    I have access to your currently open files in the editor.
    I will generate suggestions as concisely and clearly as possible.
    I only suggest something if I am certain about my answer.".to_string(),
            },
            CodyMessage {
                speaker: CodySpeaker::Human,
                text,
            },
            CodyMessage {
                speaker: CodySpeaker::Assistant,
                text: prefix.unwrap_or("".to_string()),
            },
        ];

    wrap_request!(
        sg_gql::cody_completion,
        Variables {
            messages,
            temperature,
        }
    )
}

pub async fn get_definitions(
    uri: String,
    line: i64,
    character: i64,
) -> Result<Vec<lsp_types::Location>> {
    // TODO: Could put the line and character in here directly as well...
    let remote_file = entry::Entry::new(&uri).await?;
    let remote_file = match remote_file {
        entry::Entry::File(file) => file,
        _ => return Err(anyhow::anyhow!("Can only get references of a file")),
    };

    wrap_request!(
        sg_gql::definition,
        Variables {
            repository: remote_file.remote.0,
            revision: remote_file.oid.0,
            path: remote_file.path,
            line,
            character,
        }
    )
}

pub async fn get_references(uri: String, line: i64, character: i64) -> Result<Vec<Location>> {
    let remote_file = entry::Entry::new(&uri).await?;
    let remote_file = match remote_file {
        entry::Entry::File(file) => file,
        _ => return Err(anyhow::anyhow!("Can only get references of a file")),
    };

    wrap_request!(
        sg_gql::references,
        Variables {
            repository: remote_file.remote.0,
            revision: remote_file.oid.0,
            path: remote_file.path,
            line,
            character,
        }
    )
}

pub async fn get_search(query: String) -> Result<Vec<SearchResult>> {
    wrap_request!(sg_gql::search, Variables { query })
}

pub async fn get_user_info() -> Result<UserInfo> {
    let endpoint = auth::get_endpoint();
    let token = auth::get_access_token();
    match (token, endpoint.as_str()) {
        (None, _) => Err(anyhow::anyhow!("No user information. Must log in first")),
        (Some(_), "https://sourcegraph.com") => wrap_request!(sg_gql::dotcom_user, Variables {}),
        (Some(_), _) => wrap_request!(sg_gql::enterprise_user, Variables {}),
    }
}
