with System; use System;
with Glib; use Glib;
with Gdk.Event; use Gdk.Event;
with Gdk.Types; use Gdk.Types;
with Gtk.Accel_Group; use Gtk.Accel_Group;
with Gtk.Object; use Gtk.Object;
with Gtk.Enums; use Gtk.Enums;
with Gtk.Style; use Gtk.Style;
with Gtk.Widget; use Gtk.Widget;

package body Codefix_Window_Pkg.Callbacks is

   use Gtk.Arguments;

   --------------------------
   -- On_Fix_Entry_Changed --
   --------------------------

   procedure On_Fix_Entry_Changed
     (Object : access Gtk_Widget_Record'Class)
   is
   begin
      null;
   end On_Fix_Entry_Changed;

   ---------------------
   -- On_Prev_Clicked --
   ---------------------

   procedure On_Prev_Clicked
     (Object : access Gtk_Widget_Record'Class)
   is
   begin
      null;
   end On_Prev_Clicked;

   ---------------------
   -- On_Next_Clicked --
   ---------------------

   procedure On_Next_Clicked
     (Object : access Gtk_Widget_Record'Class)
   is
   begin
      null;
   end On_Next_Clicked;

   ----------------------
   -- On_Apply_Clicked --
   ----------------------

   procedure On_Apply_Clicked
     (Object : access Gtk_Widget_Record'Class)
   is
   begin
      null;
   end On_Apply_Clicked;

   ---------------------
   -- On_Undo_Clicked --
   ---------------------

   procedure On_Undo_Clicked
     (Object : access Gtk_Widget_Record'Class)
   is
   begin
      null;
   end On_Undo_Clicked;

   ------------------------
   -- On_Refresh_Clicked --
   ------------------------

   procedure On_Refresh_Clicked
     (Object : access Gtk_Widget_Record'Class)
   is
   begin
      null;
   end On_Refresh_Clicked;

end Codefix_Window_Pkg.Callbacks;
