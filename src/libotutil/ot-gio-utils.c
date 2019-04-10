/*
 * Copyright (C) 2011 Colin Walters <walters@verbum.org>
 *
 * SPDX-License-Identifier: LGPL-2.0+
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 *
 * Author: Colin Walters <walters@verbum.org>
 */

#include "config.h"

#include <gio/gio.h>
#include <gio/gunixinputstream.h>
#include <gio/gunixoutputstream.h>
#include <gio/gfiledescriptorbased.h>

#include <string.h>

#include "otutil.h"

#ifndef O_BINARY
#define O_BINARY 0
#endif

GFile *
ot_gfile_resolve_path_printf (GFile       *path,
                              const char  *format,
                              ...)
{
  va_list args;
  g_autofree char *relpath = NULL;

  va_start (args, format);
  relpath = g_strdup_vprintf (format, args);
  va_end (args);

  return g_file_resolve_relative_path (path, relpath);
}

/**
 * ot_gfile_replace_contents_fsync:
 * 
 * Like g_file_replace_contents(), except always uses fdatasync().
 */
gboolean
ot_gfile_replace_contents_fsync (GFile          *path,
                                 GBytes         *contents,
                                 GCancellable   *cancellable,
                                 GError        **error)
{
  gsize len;
  const guint8*buf = g_bytes_get_data (contents, &len);

  return glnx_file_replace_contents_at (AT_FDCWD, gs_file_get_path_cached (path),
                                        buf, len,
                                        GLNX_FILE_REPLACE_DATASYNC_NEW,
                                        cancellable, error);
}

/**
 * ot_gfile_ensure_unlinked:
 *
 * Like gs_file_unlink(), but return successfully if the file doesn't
 * exist.
 */
gboolean
ot_gfile_ensure_unlinked (GFile         *path,
                          GCancellable  *cancellable,
                          GError       **error)
{
  if (unlink (gs_file_get_path_cached (path)) != 0)
    {
      if (errno != ENOENT)
        return glnx_throw_errno_prefix (error, "unlink(%s)", gs_file_get_path_cached (path));
    }
  return TRUE;
}

#if !GLIB_CHECK_VERSION(2, 44, 0)

gboolean
ot_file_enumerator_iterate (GFileEnumerator  *direnum,
                            GFileInfo       **out_info,
                            GFile           **out_child,
                            GCancellable     *cancellable,
                            GError          **error)
{
  gboolean ret = FALSE;
  GError *temp_error = NULL;

  static GQuark cached_info_quark;
  static GQuark cached_child_quark;
  static gsize quarks_initialized;

  g_return_val_if_fail (direnum != NULL, FALSE);
  g_return_val_if_fail (out_info != NULL, FALSE);

  if (g_once_init_enter (&quarks_initialized))
    {
      cached_info_quark = g_quark_from_static_string ("ot-cached-info");
      cached_child_quark = g_quark_from_static_string ("ot-cached-child");
      g_once_init_leave (&quarks_initialized, 1);
    }

  *out_info = g_file_enumerator_next_file (direnum, cancellable, &temp_error);
  if (out_child)
    *out_child = NULL;
  if (temp_error != NULL)
    {
      g_propagate_error (error, temp_error);
      goto out;
    }
  else if (*out_info != NULL)
    {
      g_object_set_qdata_full ((GObject*)direnum, cached_info_quark, *out_info, (GDestroyNotify)g_object_unref);
      if (out_child != NULL)
        {
          const char *name = g_file_info_get_name (*out_info);
          *out_child = g_file_get_child (g_file_enumerator_get_container (direnum), name);
          g_object_set_qdata_full ((GObject*)direnum, cached_child_quark, *out_child, (GDestroyNotify)g_object_unref);
        }
    }

  ret = TRUE;
 out:
  return ret;
}

#endif

G_LOCK_DEFINE_STATIC (pathname_cache);

/**
 * ot_file_get_path_cached:
 *
 * Like g_file_get_path(), but returns a constant copy so callers
 * don't need to free the result.
 */
const char *
ot_file_get_path_cached (GFile *file)
{
  const char *path;
  static GQuark _file_path_quark = 0;

  if (G_UNLIKELY (_file_path_quark) == 0)
    _file_path_quark = g_quark_from_static_string ("gsystem-file-path");

  G_LOCK (pathname_cache);

  path = g_object_get_qdata ((GObject*)file, _file_path_quark);
  if (!path)
    {
      path = g_file_get_path (file);
      if (path == NULL)
        {
          G_UNLOCK (pathname_cache);
          return NULL;
        }
      g_object_set_qdata_full ((GObject*)file, _file_path_quark, (char*)path, (GDestroyNotify)g_free);
    }

  G_UNLOCK (pathname_cache);

  return path;
}

/**
 * ot_file_load_contents_allow_not_found:
 *
 * Load the contents of file, allowing G_IO_ERROR_NOT_FOUND.
 * If file exists, return the contents in out_contents (otherwise out_contents
 * holds NULL).
 *
 * Return FALSE for any other error.
 */
gboolean
ot_file_load_contents_allow_not_found (GFile         *file,
                                       char         **out_contents,
                                       GCancellable  *cancellable,
                                       GError       **error)
{
  g_return_val_if_fail (file != NULL, FALSE);

  GError *local_error = NULL;
  g_autofree char *ret_contents = NULL;
  if (!g_file_load_contents (file, cancellable, &ret_contents, NULL, NULL, &local_error))
    {
      if (g_error_matches (local_error, G_IO_ERROR, G_IO_ERROR_NOT_FOUND))
        {
          g_clear_error (&local_error);
        }
      else
        {
          g_propagate_error (error, local_error);
          return FALSE;
        }
    }

  ot_transfer_out_value (out_contents, &ret_contents);
  return TRUE;
}

gboolean
ot_file_read_allow_noent (int            dfd,
                          char          *path,
                          char         **out_contents,
                          GCancellable  *cancellable,
                          GError       **error)
{
  struct stat stbuf;
  if (!glnx_fstatat_allow_noent (dfd, path, &stbuf, 0, error))
    return FALSE;
  const gboolean file_exists = (errno == 0);

  g_autofree char *ret_contents = NULL;
  if (file_exists)
    {
      ret_contents = glnx_file_get_contents_utf8_at (dfd, path, NULL,
                                                     cancellable, error);
      if (!ret_contents)
        return FALSE;
    }

  ot_transfer_out_value (out_contents, &ret_contents);
  return TRUE;
}
