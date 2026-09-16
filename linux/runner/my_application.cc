#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <glib/gstdio.h>

#include <cstdio>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Wo Groesse und Zustand des Fensters zwischen zwei Laeufen liegen.
//
// GTK merkt sich davon nichts von allein - anders als Cocoa, das dafuer
// einen Merknamen kennt. Eine winzige Textdatei im Konfigurationsordner
// des Nutzers ist der schlichteste Weg, der ohne zusaetzliche Abhaengigkeit
// auskommt; GSettings braeuchte ein eigenes Schema samt Installation.
static gchar* fenster_pfad() {
  g_autofree gchar* ordner =
      g_build_filename(g_get_user_config_dir(), "photo_vault", nullptr);
  g_mkdir_with_parents(ordner, 0700);
  return g_build_filename(ordner, "fenster", nullptr);
}

// Holt den letzten Stand. Fehlt die Datei oder steht Unsinn darin, bleibt
// es bei der Vorgabe - eine kaputte Zeile darf keinen Start verhindern.
static void fenster_stand_holen(int* breite, int* hoehe, gboolean* voll) {
  g_autofree gchar* pfad = fenster_pfad();
  g_autofree gchar* inhalt = nullptr;
  if (!g_file_get_contents(pfad, &inhalt, nullptr, nullptr)) return;
  int b = 0, h = 0, v = 0;
  if (sscanf(inhalt, "%d %d %d", &b, &h, &v) != 3) return;
  // Ein Fenster, das kleiner als handtellergross oder groesser als jeder
  // Bildschirm ist, waere unbedienbar. Solche Werte entstehen, wenn ein
  // Bildschirm abgezogen wurde.
  if (b >= 640 && h >= 480 && b <= 16384 && h <= 16384) {
    *breite = b;
    *hoehe = h;
  }
  *voll = v != 0 ? TRUE : FALSE;
}

static void fenster_stand_sichern(GtkWindow* window) {
  gboolean voll = gtk_window_is_maximized(window);
  gint breite = 0, hoehe = 0;
  // Im Vollbild liefert gtk_window_get_size die Bildschirmgroesse - dann
  // waere die vorherige Groesse verloren, sobald man einmal maximiert
  // hat. GTK haelt die letzte nicht-maximierte Groesse selbst vor.
  gtk_window_get_size(window, &breite, &hoehe);
  if (voll) {
    int alteB = breite, alteH = hoehe;
    gboolean egal = FALSE;
    fenster_stand_holen(&alteB, &alteH, &egal);
    breite = alteB;
    hoehe = alteH;
  }
  g_autofree gchar* pfad = fenster_pfad();
  g_autofree gchar* zeile =
      g_strdup_printf("%d %d %d\n", breite, hoehe, voll ? 1 : 0);
  g_file_set_contents(pfad, zeile, -1, nullptr);
}

// Beim Schliessen, nicht bei jeder Groessenaenderung: Ein configure-event
// kommt waehrend des Ziehens dutzendfach je Sekunde, und jedes davon
// waere ein Schreibvorgang auf die Platte.
static gboolean fenster_schliesst_cb(GtkWidget* widget, GdkEvent*, gpointer) {
  fenster_stand_sichern(GTK_WINDOW(widget));
  return FALSE;
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    // Der sichtbare Name, nicht die Kennung des Programms.
    gtk_header_bar_set_title(header_bar, "Photo Vault");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Photo Vault");
  }

  // Die Vorgabe gilt nur beim allerersten Start; danach steht hier die
  // Groesse, mit der zuletzt gearbeitet wurde.
  int breite = 1280;
  int hoehe = 720;
  gboolean voll = FALSE;
  fenster_stand_holen(&breite, &hoehe, &voll);
  gtk_window_set_default_size(window, breite, hoehe);
  if (voll) gtk_window_maximize(window);
  g_signal_connect(window, "delete-event", G_CALLBACK(fenster_schliesst_cb),
                   nullptr);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
