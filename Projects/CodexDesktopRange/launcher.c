#include <mach-o/dyld.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
  const char *home = getenv("HOME");
  if (home == NULL) return 1;

  char root[PATH_MAX];
  char profile[PATH_MAX];
  char codex_home[PATH_MAX];
  char user_data_arg[PATH_MAX + 32];
  snprintf(root, sizeof(root), "%s/Library/Application Support/Codex Range", home);
  snprintf(profile, sizeof(profile), "%s/Electron", root);
  snprintf(codex_home, sizeof(codex_home), "%s/Codex Home", root);
  snprintf(user_data_arg, sizeof(user_data_arg), "--user-data-dir=%s", profile);
  setenv("CODEX_ELECTRON_USER_DATA_PATH", profile, 0);
  setenv("CODEX_HOME", codex_home, 0);

  char executable[PATH_MAX];
  uint32_t executable_size = sizeof(executable);
  if (_NSGetExecutablePath(executable, &executable_size) != 0) return 1;
  char *last_slash = strrchr(executable, '/');
  if (last_slash == NULL) return 1;
  strcpy(last_slash + 1, "ChatGPT Range Runtime");

  char **runtime_argv = calloc((size_t)argc + 3, sizeof(char *));
  if (runtime_argv == NULL) return 1;
  runtime_argv[0] = executable;
  for (int i = 1; i < argc; i++) runtime_argv[i] = argv[i];
  runtime_argv[argc] = user_data_arg;
  runtime_argv[argc + 1] = "--use-mock-keychain";
  runtime_argv[argc + 2] = NULL;
  execv(executable, runtime_argv);
  perror("execv ChatGPT Range Runtime");
  return 1;
}
