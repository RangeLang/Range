use zed_extension_api::{self as zed, Result};

struct NeatExtension;

impl NeatExtension {
    const SERVER_BINARY_NAME: &'static str = "neat";
}

impl zed::Extension for NeatExtension {
    fn new() -> Self {
        Self
    }

    fn language_server_command(
        &mut self,
        language_server_id: &zed::LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<zed::Command> {
        if language_server_id.as_ref() == "neat-lsp" {
            let path = worktree.which(Self::SERVER_BINARY_NAME).ok_or_else(|| {
                "Could not find `neat` binary on PATH. Install NeatCLI first.".to_string()
            })?;

            return Ok(zed::Command {
                command: path,
                args: vec!["lsp".to_string()],
                env: worktree.shell_env(),
            });
        }

        Err(format!(
            "Neat extension does not provide language server `{}`.",
            language_server_id.as_ref()
        ))
    }
}

zed::register_extension!(NeatExtension);
