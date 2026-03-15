use zed_extension_api::{self as zed, Result};

struct NeatExtension;

impl NeatExtension {
    fn lsp_launch_script() -> String {
        r#"
if [ -x "NeatCLI/.build/arm64-apple-macosx/debug/NeatCLI" ]; then
  exec "NeatCLI/.build/arm64-apple-macosx/debug/NeatCLI" lsp
fi

if [ -x "NeatCLI/.build/debug/NeatCLI" ]; then
  exec "NeatCLI/.build/debug/NeatCLI" lsp
fi

if [ -x ".build/arm64-apple-macosx/debug/NeatCLI" ]; then
  exec ".build/arm64-apple-macosx/debug/NeatCLI" lsp
fi

if [ -x ".build/debug/NeatCLI" ]; then
  exec ".build/debug/NeatCLI" lsp
fi

if [ -x "/opt/homebrew/bin/neat" ]; then
  exec "/opt/homebrew/bin/neat" lsp
fi

if command -v neat >/dev/null 2>&1; then
  exec neat lsp
fi

echo "Could not find a Neat LSP binary. Build NeatCLI locally or install \`neat\` on PATH." >&2
exit 127
"#
        .trim()
        .to_string()
    }
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
            return Ok(zed::Command {
                command: "sh".to_string(),
                args: vec!["-lc".to_string(), Self::lsp_launch_script()],
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
