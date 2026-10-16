#include "config.h"

#include "gspawn.h"
#include "gspawn-private.h"

G_DEFINE_QUARK (g-exec-error-quark, g_spawn_error)
G_DEFINE_QUARK (g-spawn-exit-error-quark, g_spawn_exit_error)

static gboolean
spawn_not_supported (GError **error)
{
    g_set_error_literal (error,
                         G_SPAWN_ERROR,
                         G_SPAWN_ERROR_FAILED,
                         "Process spawning is not supported on Emscripten");
    return FALSE;
}

gboolean
g_spawn_sync_impl (const gchar           *working_directory,
                   gchar                **argv,
                   gchar                **envp,
                   GSpawnFlags            flags,
                   GSpawnChildSetupFunc   child_setup,
                   gpointer               user_data,
                   gchar                **standard_output,
                   gchar                **standard_error,
                   gint                  *wait_status,
                   GError               **error)
{
  if (standard_output != NULL)
    *standard_output = NULL;

  if (standard_error != NULL)
    *standard_error = NULL;

  if (wait_status != NULL)
    *wait_status = -1;

  return spawn_not_supported (error);
}

gboolean
g_spawn_async_with_pipes_and_fds_impl (const gchar           *working_directory,
                                       const gchar * const   *argv,
                                       const gchar * const   *envp,
                                       GSpawnFlags            flags,
                                       GSpawnChildSetupFunc   child_setup,
                                       gpointer               user_data,
                                       gint                   stdin_fd,
                                       gint                   stdout_fd,
                                       gint                   stderr_fd,
                                       const gint            *source_fds,
                                       const gint            *target_fds,
                                       gsize                  n_fds,
                                       GPid                  *child_pid_out,
                                       gint                  *stdin_pipe_out,
                                       gint                  *stdout_pipe_out,
                                       gint                  *stderr_pipe_out,
                                       GError               **error)
{
  if (child_pid_out != NULL)
    *child_pid_out = 0;

  if (stdin_pipe_out != NULL)
    *stdin_pipe_out = -1;

  if (stdout_pipe_out != NULL)
    *stdout_pipe_out = -1;

  if (stderr_pipe_out != NULL)
    *stderr_pipe_out = -1;

  return spawn_not_supported (error);
}

gboolean
g_spawn_check_wait_status_impl (gint     wait_status,
                                GError **error)
{
  return spawn_not_supported (error);
}

void
g_spawn_close_pid_impl (GPid pid)
{
}