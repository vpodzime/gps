-----------------------------------------------------------------------
--                               G P S                               --
--                                                                   --
--                     Copyright (C) 2003                            --
--                            ACT-Europe                             --
--                                                                   --
-- GPS is free  software;  you can redistribute it and/or modify  it --
-- under the terms of the GNU General Public License as published by --
-- the Free Software Foundation; either version 2 of the License, or --
-- (at your option) any later version.                               --
--                                                                   --
-- This program is  distributed in the hope that it will be  useful, --
-- but  WITHOUT ANY WARRANTY;  without even the  implied warranty of --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU --
-- General Public License for more details. You should have received --
-- a copy of the GNU General Public License along with this program; --
-- if not,  write to the  Free Software Foundation, Inc.,  59 Temple --
-- Place - Suite 330, Boston, MA 02111-1307, USA.                    --
-----------------------------------------------------------------------

with Glide_Kernel;             use Glide_Kernel;
with Glide_Kernel.Modules;     use Glide_Kernel.Modules;
with Glide_Kernel.Console;     use Glide_Kernel.Console;
with Gdk.Event;                use Gdk.Event;
with Gdk.Types;                use Gdk.Types;
with Gdk.Types.Keysyms;        use Gdk.Types.Keysyms;
with Glib.Xml_Int;             use Glib.Xml_Int;
with Commands.Interactive;     use Commands, Commands.Interactive;
with HTables;                  use HTables;
with GNAT.OS_Lib;              use GNAT.OS_Lib;
with GUI_Utils;                use GUI_Utils;
with System;                   use System;
with Ada.Exceptions;           use Ada.Exceptions;
with Ada.Strings.Fixed;        use Ada.Strings.Fixed;
with Gdk.Color;                use Gdk.Color;
with Gtk.Cell_Renderer_Text;   use Gtk.Cell_Renderer_Text;
with Gtk.Dialog;               use Gtk.Dialog;
with Gtk.Tree_View;            use Gtk.Tree_View;
with Gtk.Tree_Model;           use Gtk.Tree_Model;
with Gtk.Tree_Selection;       use Gtk.Tree_Selection;
with Gtk.Tree_Store;           use Gtk.Tree_Store;
with Gtk.Tree_View_Column;     use Gtk.Tree_View_Column;
with Gtk.Main;                 use Gtk.Main;
with Gtk.Menu;                 use Gtk.Menu;
with Gtk.Menu_Item;            use Gtk.Menu_Item;
with Gtk.Menu_Shell;           use Gtk.Menu_Shell;
with Gtk.Paned;                use Gtk.Paned;
with Gtk.Frame;                use Gtk.Frame;
with Gtk.GEntry;               use Gtk.GEntry;
with Gtk.Text_Buffer;          use Gtk.Text_Buffer;
with Gtk.Text_View;            use Gtk.Text_View;
with Gtk.Box;                  use Gtk.Box;
with Gtkada.Dialogs;           use Gtkada.Dialogs;
with Glib;                     use Glib;
with Glib.Object;              use Glib.Object;
with Gtk.Vbutton_Box;          use Gtk.Vbutton_Box;
with Gtk.Button;               use Gtk.Button;
with Gtk.Scrolled_Window;      use Gtk.Scrolled_Window;
with Gtk.Stock;                use Gtk.Stock;
with Glide_Intl;               use Glide_Intl;
with Gtkada.Handlers;          use Gtkada.Handlers;
with Gtk.Widget;               use Gtk.Widget;
with Gtk.Enums;                use Gtk.Enums;
with System;                   use System;
with Gtk.Accel_Map;            use Gtk.Accel_Map;
with Gtk.Window;               use Gtk.Window;
with Gtk.Event_Box;            use Gtk.Event_Box;
with Gtk.Label;                use Gtk.Label;
with Gtk.Style;                use Gtk.Style;
with Gtk.Separator;            use Gtk.Separator;
with Traces;                   use Traces;
with Glide_Main_Window;        use Glide_Main_Window;
with Ada.Unchecked_Deallocation;
with Ada.Unchecked_Conversion;

package body KeyManager_Module is

   Me : constant Debug_Handle := Create ("Keymanager");

   Menu_Context_Name : constant String := "Menus";
   --  -"Menus" will need to be translated

   type Keys_Header_Num is range 0 .. 1000;
   type Key_Binding is record
      Key      : Gdk_Key_Type;
      Modifier : Gdk_Modifier_Type;
   end record;
   No_Binding : constant Key_Binding := (0, 0);

   type Keymap_Record;
   type Keymap_Access is access Keymap_Record;

   type Key_Description;
   type Key_Description_List is access Key_Description;
   type Key_Description is record
      Action  : String_Access;
      Changed : Boolean := False;
      Next    : Key_Description_List;
   end record;
   No_Key : constant Key_Description_List := null;
   --  Changed is set to True when the key was customized from within GPS
   --  itself, and should therefore be saved on exit. It is false for values
   --  read from the custom files.
   --
   --  To save memory, the following encoding is used: if Action is null,
   --  this key binding is associated with a secondary keymap (for instance
   --  as in "control-x control-k". In that case, Next is of type
   --  Keymap_Access.

   function Next (Key : Key_Description_List) return Key_Description_List;
   --  Return the next element in the list

   function Get_Keymap (Key : Key_Description_List) return Keymap_Access;
   --  Return the secondary keymap associated with Key.

   procedure Unchecked_Free is new Ada.Unchecked_Deallocation
     (Key_Description, Key_Description_List);

   function Hash (Key : Key_Binding) return Keys_Header_Num;
   procedure Free (Element : in out Key_Description_List);
   --  Support functions for creating the htable

   package Key_Htable is new Simple_HTable
     (Header_Num   => Keys_Header_Num,
      Element      => Key_Description_List,
      Free_Element => Free,
      No_Element   => No_Key,
      Key          => Key_Binding,
      Hash         => Hash,
      Equal        => "=");
   use Key_Htable;

   type Keymap_Record is record
      Table : Key_Htable.HTable;
   end record;

   procedure Unchecked_Free is new Ada.Unchecked_Deallocation
     (Keymap_Record, Keymap_Access);

   type Key_Manager_Record is new Glide_Kernel.Key_Handler_Record with record
      Kernel : Kernel_Handle;
      Table  : Key_Htable.HTable;

      Secondary_Keymap : Keymap_Access := null;
      --  The secondary keymap currently in use, or null if using the primary.

      Active : Boolean := True;
      --  Whether the key manager should process the key events. This is only
      --  deactivated while editing the key bindings through the GUI.
   end record;
   type Key_Manager_Access is access all Key_Manager_Record'Class;

   procedure Bind_Default_Key
     (Handler        : access Key_Manager_Record;
      Action         : String;
      Default_Key    : String);
   function Process_Event
     (Handler  : access Key_Manager_Record;
      Event    : Gdk_Event) return Boolean;
   procedure Free (Handler : in out Key_Manager_Record);
   --  See documentation for imported subprograms

   procedure Bind_Default_Key_Internal
     (Table          : in out Key_Htable.HTable;
      Action         : String;
      Default_Key    : Gdk.Types.Gdk_Key_Type;
      Default_Mod    : Gdk.Types.Gdk_Modifier_Type;
      Changed        : Boolean := False);
   --  Internal version that allows setting the Changed attribute.

   procedure Bind_Default_Key_Internal
     (Handler        : access Key_Manager_Record'Class;
      Action         : String;
      Default_Key    : String;
      Changed        : Boolean := False);
   --  Same as above, except Default_Key can also include secondary keymaps
   --  as in "control-c control-k"

   procedure Load_Custom_Keys
     (Kernel  : access Kernel_Handle_Record'Class;
      Manager : access Key_Manager_Record'Class);
   --  Load the customized key bindings

   procedure On_Edit_Keys
     (Widget : access GObject_Record'Class; Kernel : Kernel_Handle);
   --  Open a GUI to edit the key bindings

   procedure On_Grab_Key (Editor : access Gtk_Widget_Record'Class);
   procedure On_Remove_Key (Editor : access Gtk_Widget_Record'Class);
   procedure On_Add_Key (Editor : access Gtk_Widget_Record'Class);
   --  Handle the "Grab", "Remove" and "Add" buttons

   function Grab_Multiple_Key
     (Widget : access Gtk_Widget_Record'Class;
      Allow_Multiple : Boolean)
      return String;
   --  Grab a key binding, with support for multiple keymaps. Returns the
   --  empty string if no key could be grabbed.

   function Cancel_Grab return Boolean;
   --  Exit the current nest main loop, if any

   type Keys_Editor_Record is new Gtk_Dialog_Record with record
      Kernel  : Kernel_Handle;
      View    : Gtk_Tree_View;
      Model   : Gtk_Tree_Store;
   end record;
   type Keys_Editor is access all Keys_Editor_Record'Class;

   type Add_Editor_Record is new Gtk_Dialog_Record with record
      View        : Gtk_Tree_View;
      Model       : Gtk_Tree_Store;
      Help        : Gtk_Text_Buffer;
      Grab        : Gtk_Entry;
      Action_Name : Gtk_Label;
      Kernel      : Kernel_Handle;
   end record;
   type Add_Editor is access all Add_Editor_Record'Class;

   procedure Fill_Editor (Editor : access Keys_Editor_Record'Class);
   --  Fill the contents of the editor

   procedure Save_Editor (Editor : access Keys_Editor_Record'Class);
   --  Save the contents of the editor

   function Set
     (Model   : Gtk_Tree_Store;
      Parent  : Gtk_Tree_Iter;
      Descr   : String;
      Changed : Boolean := False;
      Key     : String := "") return Gtk_Tree_Iter;
   --  Add a new line into the model

   procedure Lookup_Command_By_Name
     (Handler : access Key_Manager_Record'Class;
      Action  : String;
      Keymap  : out Keymap_Access;
      Key     : out Key_Binding;
      Binding : out Key_Description_List);
   --  Search the description of a command in the table

   procedure Add_Selection_Changed (Dialog : access Gtk_Widget_Record'Class);
   --  Called when the selection in the "Add" dialog has changed

   procedure Add_Dialog_Grab (Dialog : access Gtk_Widget_Record'Class);
   --  Called when "grab" is pressed in the "Add" dialog.

   procedure Get_Secondary_Keymap
     (Table  : in out Key_Htable.HTable;
      Key    : Gdk_Key_Type;
      Modif  : Gdk_Modifier_Type;
      Keymap : out Keymap_Access);
   --  Get or create a secondary keymap in Table.

   function Find_Parent
     (Model : Gtk_Tree_Store; Context : Action_Context) return Gtk_Tree_Iter;
   function Find_Parent
     (Model : Gtk_Tree_Store; Context : String) return Gtk_Tree_Iter;
   --  Find the parent node for Context.
   --  Returns null if there is no such node


   Action_Column  : constant := 0;
   Key_Column     : constant := 1;
   Changed_Column : constant := 2;

   ----------
   -- Next --
   ----------

   function Next (Key : Key_Description_List) return Key_Description_List is
   begin
      if Key.Action = null then
         --  A secondary keymap in fact
         return null;
      else
         return Key.Next;
      end if;
   end Next;

   ----------------
   -- Get_Keymap --
   ----------------

   function Get_Keymap (Key : Key_Description_List) return Keymap_Access is
      function Convert is new Ada.Unchecked_Conversion
        (Key_Description_List, Keymap_Access);
   begin
      if Key.Action = null then
         return Convert (Key.Next);
      else
         return null;
      end if;
   end Get_Keymap;

   ----------
   -- Hash --
   ----------

   function Hash (Key : Key_Binding) return Keys_Header_Num is
   begin
      return Keys_Header_Num
        ((Integer (Key.Key) + Integer (Key.Modifier) * 16#FFFF#)
          mod Integer (Keys_Header_Num'Last + 1));
   end Hash;

   ----------
   -- Free --
   ----------

   procedure Free (Element : in out Key_Description_List) is
      Current : Key_Description_List := Element;
      N       : Key_Description_List;
      Keymap  : Keymap_Access;
   begin
      while Current /= null loop
         N := Next (Current);

         if Current.Action = null then
            Keymap := Get_Keymap (Current);
            Reset (Keymap.Table);
            Unchecked_Free (Keymap);
         else
            Free (Current.Action);
         end if;
         Unchecked_Free (Current);
         Current := N;
      end loop;
   end Free;

   ----------------------------
   -- Lookup_Command_By_Name --
   ----------------------------

   procedure Lookup_Command_By_Name
     (Handler : access Key_Manager_Record'Class;
      Action  : String;
      Keymap  : out Keymap_Access;
      Key     : out Key_Binding;
      Binding : out Key_Description_List)
   is
      procedure Process_Table
        (Table : in out Key_Htable.HTable; Found : out Boolean);
      --  Process a keymap..

      procedure Process_Table
        (Table : in out Key_Htable.HTable; Found : out Boolean)
      is
         Iter : Key_Htable.Iterator;
         Bind : Key_Description_List;
      begin
         Get_First (Table, Iter);
         loop
            Bind := Get_Element (Iter);
            exit when Bind = No_Key;

            while Bind /= null loop
               if Bind.Action /= null then
                  if Bind.Action.all = Action then
                     Key     := Get_Key (Iter);
                     Binding := Bind;
                     Found   := True;
                     return;
                  end if;
               else
                  Process_Table (Get_Keymap (Bind).Table, Found);
                  if Found then
                     return;
                  end if;
               end if;
               Bind := Next (Bind);
            end loop;

            Get_Next (Table, Iter);
         end loop;
         Found := False;
      end Process_Table;

      Found : Boolean;
   begin
      --  We do not use the most efficient method, since we simply
      --  traverse a list, but there aren't hundreds of keybindings...

      Process_Table (Handler.Table, Found);

      if not Found then
         Keymap  := null;
         Key     := No_Binding;
         Binding := null;
      end if;
   end Lookup_Command_By_Name;

   ----------------------
   -- Bind_Default_Key --
   ----------------------

   procedure Bind_Default_Key
     (Handler        : access Key_Manager_Record;
      Action         : String;
      Default_Key    : String) is
   begin
      Bind_Default_Key_Internal
        (Handler, Action, Default_Key, Changed => False);
   end Bind_Default_Key;

   -------------------------------
   -- Bind_Default_Key_Internal --
   -------------------------------

   procedure Bind_Default_Key_Internal
     (Table          : in out Key_Htable.HTable;
      Action         : String;
      Default_Key    : Gdk.Types.Gdk_Key_Type;
      Default_Mod    : Gdk.Types.Gdk_Modifier_Type;
      Changed        : Boolean := False)
   is
      Binding, Binding2 : Key_Description_List;
   begin
      Binding2 := new Key_Description'
        (Action         => new String'(Action),
         Changed        => Changed,
         Next           => null);
      Binding := Get (Table, Key_Binding'(Default_Key, Default_Mod));

      if Binding /= null then
         Binding2.Next := Binding.Next;
         Binding.Next  := Binding2;
      else
         Set (Table, Key_Binding'(Default_Key, Default_Mod), Binding2);
      end if;
   end Bind_Default_Key_Internal;

   -------------------------------
   -- Bind_Default_Key_Internal --
   -------------------------------

   procedure Bind_Default_Key_Internal
     (Handler        : access Key_Manager_Record'Class;
      Action         : String;
      Default_Key    : String;
      Changed        : Boolean := False)
   is
      Key   : Gdk_Key_Type;
      Modif : Gdk_Modifier_Type;
      First, Last : Integer;
      Keymap  : Keymap_Access;
      Binding : Key_Description_List;
      Bind    : Key_Binding;
   begin
      Lookup_Command_By_Name (Handler, Action, Keymap, Bind, Binding);
      if Binding /= null then
         --  Keep the current key binding, since it was probably
         --  customized by the user
         Binding.Changed := Binding.Changed or else Changed;
         return;
      end if;

      First := Default_Key'First;
      while First <= Default_Key'Last loop
         Last := First + 1;
         while Last <= Default_Key'Last and then Default_Key (Last) /= ' ' loop
            Last := Last + 1;
         end loop;

         Value (Default_Key (First .. Last - 1), Key, Modif);

         if Last > Default_Key'Last then
            if Keymap = null then
               Bind_Default_Key_Internal
                 (Handler.Table, Action, Key, Modif, Changed);
            else
               Bind_Default_Key_Internal
                 (Keymap.Table, Action, Key, Modif, Changed);
            end if;

         else
            if Keymap = null then
               Get_Secondary_Keymap (Handler.Table, Key, Modif, Keymap);
            else
               Get_Secondary_Keymap (Keymap.Table, Key, Modif, Keymap);
            end if;
         end if;

         First := Last + 1;
      end loop;
   end Bind_Default_Key_Internal;

   --------------------------
   -- Get_Secondary_Keymap --
   --------------------------

   procedure Get_Secondary_Keymap
     (Table  : in out Key_Htable.HTable;
      Key    : Gdk_Key_Type;
      Modif  : Gdk_Modifier_Type;
      Keymap : out Keymap_Access)
   is
      function Convert is new Ada.Unchecked_Conversion
        (Keymap_Access, Key_Description_List);
      Binding  : Key_Description_List := Get (Table, (Key, Modif));
      Binding2 : Key_Description_List;
   begin
      if Binding = null then
         Keymap := new Keymap_Record;
         Binding := new Key_Description'
           (Action  => null,
            Changed => False,
            Next    => Convert (Keymap));
         Set (Table, (Key, Modif), Binding);

      else
         Binding2 := Binding;
         while Binding2.Action /= null loop
            Binding  := Binding2;  --  Last value where Next /= null
            Binding2 := Next (Binding2);
         end loop;

         if Binding2 = null then
            Keymap   := new Keymap_Record;
            Binding2 := new Key_Description'
              (Action  => null,
               Changed => False,
               Next    => Convert (Keymap));
            Binding.Next := Binding2;
         else
            Keymap := Get_Keymap (Binding2);
         end if;
      end if;
   end Get_Secondary_Keymap;

   -------------------
   -- Process_Event --
   -------------------

   function Process_Event
     (Handler  : access Key_Manager_Record;
      Event    : Gdk.Event.Gdk_Event) return Boolean
   is
      Key     : constant Gdk_Key_Type      := Get_Key_Val (Event);
      Modif   : constant Gdk_Modifier_Type := Get_State (Event);
      Binding : Key_Description_List;
      Command : Action_Record;
      Any_Context_Command : Action_Record := No_Action;
      Has_Secondary : constant Boolean := Handler.Secondary_Keymap /= null;
   begin
      if Handler.Active
        and then Get_Event_Type (Event) = Key_Press
      then
         if Handler.Secondary_Keymap = null then
            Binding := Get (Handler.Table, (Key, Modif));
         else
            Binding := Get (Handler.Secondary_Keymap.Table, (Key, Modif));
         end if;

         Handler.Secondary_Keymap := null;

         while Binding /= No_Key loop
            if Binding.Action = null then
               Handler.Secondary_Keymap := Get_Keymap (Binding);
               return True;

            else
               Command := Lookup_Action (Handler.Kernel, Binding.Action.all);

               if Command.Command /= null then
                  --  We'll have to test last the commands that apply anywhere,
                  --  to give a chance to more specialized commands to get
                  --  called first.
                  if Command.Context = null then
                     Any_Context_Command := Command;
                     Trace (Me, "Candidate action in any context: "
                            & Binding.Action.all);

                  elsif Context_Matches (Command.Context, Handler.Kernel) then
                     Trace (Me, "Executing action " & Binding.Action.all);
                     if Execute (Command.Command, Event) = Success then
                        return True;
                     end if;
                  end if;
               end if;
            end if;

            Binding := Next (Binding);
         end loop;

         if Any_Context_Command /= No_Action then
            Trace (Me, "Executing any context action");
            if Execute (Any_Context_Command.Command, Event) = Success then
               return True;
            end if;
         end if;
      end if;

      --  Never pass through an event from a secondary keymap
      return Has_Secondary;
   end Process_Event;

   ----------
   -- Free --
   ----------

   procedure Free (Handler : in out Key_Manager_Record) is
      Filename : constant String := Get_Home_Dir (Handler.Kernel) & "keys.xml";
      File : Node_Ptr;

      procedure Save_Table (Table : in out Key_Htable.HTable; Prefix : String);
      --  Save the contents of a specific keymap

      procedure Save_Table
        (Table : in out Key_Htable.HTable; Prefix : String)
      is
         Child : Node_Ptr;
         Iter : Key_Htable.Iterator;
         Binding : Key_Description_List;
      begin
         Get_First (Table, Iter);
         loop
            Binding := Get_Element (Iter);
            exit when Binding = No_Key;

            while Binding /= null loop
               if Binding.Changed
                 and then Binding.Action /= null
               then
                  Child := new Node;
                  Child.Tag := new String'("Key");
                  Set_Attribute (Child, "action", Binding.Action.all);
                  Child.Value := new String'
                    (Prefix
                     & Image (Get_Key (Iter).Key, Get_Key (Iter).Modifier));

                  Add_Child (File, Child);

               elsif Binding.Action = null then
                  Save_Table (Get_Keymap (Binding).Table,
                              Prefix
                              & Image (Get_Key (Iter).Key,
                                       Get_Key (Iter).Modifier)
                              & ' ');
               end if;

               Binding := Next (Binding);
            end loop;

            Get_Next (Table, Iter);
         end loop;
      end Save_Table;

   begin
      File     := new Node;
      File.Tag := new String'("Keys");

      Save_Table (Handler.Table, "");

      Trace (Me, "Saving " & Filename);
      Print (File, Filename);
      Free (File);

      Reset (Handler.Table);
   end Free;

   ----------------------
   -- Load_Custom_Keys --
   ----------------------

   procedure Load_Custom_Keys
     (Kernel  : access Kernel_Handle_Record'Class;
      Manager : access Key_Manager_Record'Class)
   is
      Filename : constant String := Get_Home_Dir (Kernel) & "keys.xml";
      File, Child : Node_Ptr;
   begin
      if Is_Regular_File (Filename) then
         Trace (Me, "Loading " & Filename);
         File := Parse (Filename);
         Child := File.Child;

         while Child /= null loop
            Bind_Default_Key_Internal
              (Manager,
               Action      => Get_Attribute (Child, "action"),
               Default_Key => Child.Value.all,
               Changed     => True);
            Child := Child.Next;
         end loop;

         Free (File);
      end if;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
         Insert (Kernel, -"Could not parse " & Filename, Mode => Error);
   end Load_Custom_Keys;

   -----------------
   -- Find_Parent --
   -----------------

   function Find_Parent
     (Model : Gtk_Tree_Store; Context : String) return Gtk_Tree_Iter
   is
      Parent : Gtk_Tree_Iter := Get_Iter_First (Model);
   begin
      while Parent /= Null_Iter loop
         if Get_String (Model, Parent, Action_Column) = Context then
            return Parent;
         end if;
         Next (Model, Parent);
      end loop;

      return Null_Iter;
   end Find_Parent;

   -----------------
   -- Find_Parent --
   -----------------

   function Find_Parent
     (Model : Gtk_Tree_Store; Context : Action_Context) return Gtk_Tree_Iter
   is
   begin
      if Context = null then
         return Find_Parent (Model, -"General");
      else
         return Find_Parent (Model, Get_Name (Context));
      end if;
   end Find_Parent;

   ---------
   -- Set --
   ---------

   function Set
     (Model   : Gtk_Tree_Store;
      Parent  : Gtk_Tree_Iter;
      Descr   : String;
      Changed : Boolean := False;
      Key     : String := "") return Gtk_Tree_Iter
   is
      procedure Internal
        (Tree, Iter : System.Address;
         Col1  : Gint; Value1 : String;
         Col2  : Gint; Value2 : String;
         Col3  : Gint; Value3 : Gboolean;
         Final : Gint := -1);
      pragma Import (C, Internal, "gtk_tree_store_set");

      Iter : Gtk_Tree_Iter;
   begin
      Append (Model, Iter, Parent);
      Internal
        (Get_Object (Model), Iter'Address,
         Col1 => Action_Column,  Value1 => Descr & ASCII.NUL,
         Col2 => Key_Column,     Value2 => Key & ASCII.NUL,
         Col3 => Changed_Column, Value3 => Boolean'Pos (Changed));
      return Iter;
   end Set;

   -----------------
   -- Fill_Editor --
   -----------------

   procedure Fill_Editor (Editor : access Keys_Editor_Record'Class) is
      Menu_Iter : Gtk_Tree_Iter;
      Handler      : constant Key_Manager_Access := Key_Manager_Access
        (Get_Key_Handler (Editor.Kernel));

      procedure Process_Menu_Binding
        (Data       : System.Address;
         Accel_Path : String;
         Accel_Key  : Gdk.Types.Gdk_Key_Type;
         Accel_Mods : Gdk.Types.Gdk_Modifier_Type;
         Changed    : Boolean);
      --  Called for each key binding associated with menus

      procedure Process_Table
        (Table : in out Key_Htable.HTable; Prefix : String);
      --  Process the contents of a specific keymap

      --------------------------
      -- Process_Menu_Binding --
      --------------------------

      procedure Process_Menu_Binding
        (Data       : System.Address;
         Accel_Path : String;
         Accel_Key  : Gdk.Types.Gdk_Key_Type;
         Accel_Mods : Gdk.Types.Gdk_Modifier_Type;
         Changed    : Boolean)
      is
         Iter : Gtk_Tree_Iter;
         pragma Unreferenced (Data, Changed, Iter);
         First : constant Natural := Accel_Path'First;
      begin
--  Temporarily commented out, we'll show the leading <gps> prefix anyway.
--  We need it to update the menus dynamically on exit, and GPS uses both
--  <gps> and <gtkada>. An extra column should be added to store this prefix
--           while First <= Accel_Path'Last
--             and then Accel_Path (First) /= '/'
--           loop
--              First := First + 1;
--           end loop;

         if Accel_Key /= 0 then
            Iter := Set (Model  => Editor.Model,
                         Parent => Menu_Iter,
                         Descr  => Accel_Path (First .. Accel_Path'Last),
                         Changed => False,
                         Key    => Image (Accel_Key, Accel_Mods));
         end if;
      end Process_Menu_Binding;

      -------------------
      -- Process_Table --
      -------------------

      procedure Process_Table
        (Table : in out Key_Htable.HTable; Prefix : String)
      is
         Iter    : Key_Htable.Iterator;
         Binding : Key_Description_List;
         Parent  : Gtk_Tree_Iter;
         Action  : Action_Record;
      begin
         Get_First (Table, Iter);
         loop
            Binding := Get_Element (Iter);
            exit when Binding = No_Key;

            while Binding /= null loop
               if Binding.Action = null then
                  Process_Table
                    (Get_Keymap (Binding).Table,
                     Prefix
                     & Image (Get_Key (Iter).Key,
                              Get_Key (Iter).Modifier) & ' ');

               else
                  Action := Lookup_Action (Handler.Kernel, Binding.Action.all);
                  if Action /= No_Action then
                     Parent := Find_Parent (Editor.Model, Action.Context);
                     if Parent = Null_Iter then
                        if Action.Context = null then
                           Parent := Set
                             (Editor.Model, Null_Iter, Descr => -"General");
                        else
                           Parent := Set
                             (Editor.Model, Null_Iter,
                              Get_Name (Action.Context));
                        end if;
                     end if;

                     Parent := Set
                       (Model   => Editor.Model,
                        Parent  => Parent,
                        Descr   => Binding.Action.all,
                        Changed => Binding.Changed,
                        Key     => Prefix & Image (Get_Key (Iter).Key,
                                                   Get_Key (Iter).Modifier));
                  end if;
               end if;
               Binding := Next (Binding);
            end loop;

            Get_Next (Table, Iter);
         end loop;
      end Process_Table;

      Sort_Id      : constant Gint := Freeze_Sort (Editor.Model);
   begin
      Clear (Editor.Model);

      Menu_Iter := Set (Editor.Model, Null_Iter, -Menu_Context_Name);

      Gtk.Accel_Map.Foreach
        (System.Null_Address, Process_Menu_Binding'Unrestricted_Access);
      Process_Table (Handler.Table, "");

      Thaw_Sort (Editor.Model, Sort_Id);
   end Fill_Editor;

   -----------------
   -- Save_Editor --
   -----------------

   procedure Save_Editor (Editor : access Keys_Editor_Record'Class) is
      Handler      : constant Key_Manager_Access := Key_Manager_Access
        (Get_Key_Handler (Editor.Kernel));
      Context_Iter : Gtk_Tree_Iter := Get_Iter_First (Editor.Model);
      Child        : Gtk_Tree_Iter;
      Key          : Gdk_Key_Type;
      Modif        : Gdk_Modifier_Type;
   begin
      Reset (Handler.Table);

      while Context_Iter /= Null_Iter loop
         --  Special handling for menus

         if Get_String (Editor.Model, Context_Iter, Action_Column) =
           -Menu_Context_Name
         then
            Child := Children (Editor.Model, Context_Iter);
            while Child /= Null_Iter loop
               Value (Get_String (Editor.Model, Child, Key_Column),
                      Key, Modif);
               Change_Entry
                 (Accel_Path =>
                    Get_String (Editor.Model, Child, Action_Column),
                  Accel_Key  => Key,
                  Accel_Mods => Modif,
                  Replace => True);
               Next (Editor.Model, Child);
            end loop;

         --  Standard key bindings
         else
            Child := Children (Editor.Model, Context_Iter);
            while Child /= Null_Iter loop
               Bind_Default_Key_Internal
                 (Handler,
                  Action       =>
                    Get_String (Editor.Model, Child, Action_Column),
                  Default_Key  => Get_String (Editor.Model, Child, Key_Column),
                  Changed => Get_Boolean
                    (Editor.Model, Child, Changed_Column));
               Next (Editor.Model, Child);
            end loop;
         end if;

         Next (Editor.Model, Context_Iter);
      end loop;
   end Save_Editor;

   -----------------
   -- Cancel_Grab --
   -----------------

   function Cancel_Grab return Boolean is
   begin
      --  If there is a grab pending
      if Main_Level > 1 then
         Main_Quit;
      end if;
      return False;
   end Cancel_Grab;

   -----------------------
   -- Grab_Multiple_Key --
   -----------------------

   function Grab_Multiple_Key
     (Widget : access Gtk_Widget_Record'Class;
      Allow_Multiple : Boolean)
      return String
   is
      Grabbed, Tmp : String_Access;
      Key   : Gdk_Key_Type;
      Modif : Gdk_Modifier_Type;
      Id    : Timeout_Handler_Id;

   begin
      Key_Grab (Widget, Key, Modif);
      if Key /= GDK_Escape or else Modif /= 0 then
         Grabbed := new String'(Image (Key, Modif));
      else
         return "";
      end if;

      --  Are we grabbing multiple keymaps ?

      if Allow_Multiple then
         loop
            Id := Timeout_Add (500, Cancel_Grab'Access);
            Key_Grab (Widget, Key, Modif);
            Timeout_Remove (Id);

            exit when Key = 0 and then Modif = 0;

            if Key = GDK_Escape and then Modif = 0 then
               Free (Grabbed);
               return "";
            end if;

            Tmp := Grabbed;
            Grabbed := new String'(Grabbed.all & ' ' & Image (Key, Modif));
            Free (Tmp);
         end loop;
      end if;

      declare
         K : constant String := Grabbed.all;
      begin
         Free (Grabbed);
         return K;
      end;
   end Grab_Multiple_Key;

   -----------------
   -- On_Grab_Key --
   -----------------

   procedure On_Grab_Key (Editor : access Gtk_Widget_Record'Class) is
      Ed        : constant Keys_Editor := Keys_Editor (Editor);
      Handler   : constant Key_Manager_Access :=
        Key_Manager_Access (Get_Key_Handler (Ed.Kernel));
      Selection : constant Gtk_Tree_Selection := Get_Selection (Ed.View);
      Model     : Gtk_Tree_Model;
      Iter      : Gtk_Tree_Iter;
   begin
      Get_Selected (Selection, Model, Iter);

      --  Only edit for leaf nodes (otherwise these are contexts)
      if Iter /= Null_Iter
        and then Children (Model, Iter) = Null_Iter
      then
         Handler.Active := False;

         declare
            Is_Menu : constant Boolean := Get_String
              (Model, Parent (Model, Iter), Action_Column) =
              -Menu_Context_Name;
            Key : constant String := Grab_Multiple_Key
              (Ed.View, Allow_Multiple => not Is_Menu);
         begin
            if Key /= "" then
               Set (Ed.Model, Iter, Key_Column, Key);
               Set (Ed.Model, Iter, Changed_Column, True);
            end if;
         end;

         Handler.Active := True;
      end if;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception " & Exception_Information (E));
   end On_Grab_Key;

   -------------------
   -- On_Remove_Key --
   -------------------

   procedure On_Remove_Key (Editor : access Gtk_Widget_Record'Class) is
      Ed        : constant Keys_Editor := Keys_Editor (Editor);
      Selection : constant Gtk_Tree_Selection := Get_Selection (Ed.View);
      Model     : Gtk_Tree_Model;
      Iter, P   : Gtk_Tree_Iter;
   begin
      Get_Selected (Selection, Model, Iter);

      --  Only edit for leaf nodes (otherwise these are contexts)
      if Iter /= Null_Iter
        and then Children (Model, Iter) = Null_Iter
      then
         P := Parent (Ed.Model, Iter);
         Remove (Ed.Model, Iter);
         if Children (Model, P) = Null_Iter then
            Remove (Ed.Model, P);
         end if;
      end if;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception " & Exception_Information (E));
   end On_Remove_Key;

   ---------------------------
   -- Add_Selection_Changed --
   ---------------------------

   procedure Add_Selection_Changed (Dialog : access Gtk_Widget_Record'Class) is
      D : constant Add_Editor := Add_Editor (Dialog);
      Selection : constant Gtk_Tree_Selection := Get_Selection (D.View);
      Model     : Gtk_Tree_Model;
      Iter      : Gtk_Tree_Iter;
      Action    : Action_Record;
   begin
      Get_Selected (Selection, Model, Iter);

      --  Only edit for leaf nodes (otherwise these are contexts)
      if Iter /= Null_Iter
        and then Children (Model, Iter) = Null_Iter
      then
         Action := Lookup_Action (D.Kernel, Get_String (Model, Iter, 0));

         if Action.Description /= null then
            Set_Text (D.Help, Action.Description.all);
         else
            Set_Text (D.Help, "");
         end if;

         Set_Text (D.Action_Name, Get_String (Model, Iter, 0));
      end if;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception " & Exception_Information (E));
   end Add_Selection_Changed;

   ---------------------
   -- Add_Dialog_Grab --
   ---------------------

   procedure Add_Dialog_Grab (Dialog : access Gtk_Widget_Record'Class) is
      D   : constant Add_Editor := Add_Editor (Dialog);
      Handler   : constant Key_Manager_Access :=
        Key_Manager_Access (Get_Key_Handler (D.Kernel));
   begin
      Handler.Active := False;

      declare
         Key : constant String := Grab_Multiple_Key (D.Grab, True);
      begin
         if Key /= "" then
            Set_Text (D.Grab, Key);
         end if;
      end;

      Handler.Active := True;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception " & Exception_Information (E));
   end Add_Dialog_Grab;

   ----------------
   -- On_Add_Key --
   ----------------

   procedure On_Add_Key (Editor : access Gtk_Widget_Record'Class) is
      function Set
        (Model   : Gtk_Tree_Store;
         Name    : String;
         Parent  : Gtk_Tree_Iter := Null_Iter) return Gtk_Tree_Iter;
      --  Add a new line into the model

      procedure Add_Menu
        (Model  : Gtk_Tree_Store;
         Parent : Gtk_Tree_Iter;
         Menu   : access Gtk_Menu_Shell_Record'Class;
         Path   : String);
      --  Add all the menus and submenus of Menu as children of Parent

      --------------
      -- Add_Menu --
      --------------

      procedure Add_Menu
        (Model  : Gtk_Tree_Store;
         Parent : Gtk_Tree_Iter;
         Menu   : access Gtk_Menu_Shell_Record'Class;
         Path   : String)
      is
         use Widget_List;
         Children : Widget_List.Glist := Get_Children (Menu);
         Tmp      : Widget_List.Glist := First (Children);
         W, Child : Gtk_Widget;
         Iter     : Gtk_Tree_Iter;
         pragma Unreferenced (Iter);
      begin
         while Tmp /= Null_List loop
            W := Get_Data (Tmp);
            if W.all in Gtk_Menu_Record'Class then
               Add_Menu (Model, Parent,
                         Gtk_Menu (W),
                         Path & Get_Title (Gtk_Menu (W)) & '/');

            elsif W.all in Gtk_Menu_Shell_Record'Class then
               Add_Menu (Model, Parent, Gtk_Menu_Shell (W), Path);

            elsif W.all in Gtk_Menu_Item_Record'Class then
               --  ??? The best thing would be to get the accel_path for W.
               --  However, the function _gtk_widget_get_accel_path is not
               --  exported by gtk+, so we have to emulate this as best we
               --  can...
               --
               --  This approach is however not really good, since menus
               --  with no accel_path are still referenced. Maybe we should
               --  generate the accel_path on the fly when saving this dialog.

               Child := Get_Child (Gtk_Menu_Item (W));

               --  Child is null for separators

               if Child /= null then
                  --  The child is not an accel label only for togglemenu items
                  --  as far as could be seen (Window menu), and we do not want
                  --  to generate shortcuts for these anyway

                  if Child.all in Gtk_Label_Record'Class then
                     declare
                        Label : constant String :=
                          Get_Text (Gtk_Label (Child));
                     begin
                        if Get_Submenu (Gtk_Menu_Item (W)) /= null then
                           Add_Menu
                             (Model, Parent,
                              Gtk_Menu_Shell (Get_Submenu (Gtk_Menu_Item (W))),
                              Path & Label & '/');

                        else
                           Iter := Set (Model, Path & Label, Parent);
                        end if;
                     end;
                  end if;
               end if;
            end if;

            Tmp := Next (Tmp);
         end loop;

         Free (Children);
      end Add_Menu;

      ---------
      -- Set --
      ---------

      function Set
        (Model   : Gtk_Tree_Store;
         Name    : String;
         Parent  : Gtk_Tree_Iter := Null_Iter) return Gtk_Tree_Iter
      is
         procedure Internal
           (Tree, Iter : System.Address;
            Col1  : Gint; Value1 : String;
            Final : Gint := -1);
         pragma Import (C, Internal, "gtk_tree_store_set");

         Iter : Gtk_Tree_Iter;
      begin
         Append (Model, Iter, Parent);
         Internal
           (Get_Object (Model), Iter'Address,
            Col1 => Action_Column,  Value1 => Name & ASCII.NUL);
         return Iter;
      end Set;

      Ed        : constant Keys_Editor := Keys_Editor (Editor);
      Hbox      : Gtk_Box;
      Pane      : Gtk_Paned;
      Dialog    : Add_Editor;
      Button    : Gtk_Widget;
      Text      : Gtk_Text_View;
      Scrolled  : Gtk_Scrolled_Window;
      Col       : Gtk_Tree_View_Column;
      Render    : Gtk_Cell_Renderer_Text;
      Action_Iter : Action_Iterator;
      Action    : Action_Record;
      Parent    : Gtk_Tree_Iter;
      Grab      : Gtk_Button;
      Num       : Gint;
      Event     : Gtk_Event_Box;
      Frame     : Gtk_Frame;
      Sep       : Gtk_Separator;
      Color     : Gdk_Color;
      pragma Unreferenced (Button, Num);

   begin
      Dialog := new Add_Editor_Record;
      Initialize (Dialog,
                  Title  => -"Add key binding",
                  Parent => Gtk_Window (Editor),
                  Flags  => Modal or Destroy_With_Parent);
      Set_Default_Size (Dialog, 640, 480);

      Dialog.Kernel := Ed.Kernel;

      Gtk_New (Dialog.Model, (0 => GType_String));
      Gtk_New (Dialog.View, Dialog.Model);

      Widget_Callback.Object_Connect
        (Get_Selection (Dialog.View), "changed",
         Widget_Callback.To_Marshaller (Add_Selection_Changed'Access),
         Dialog);

      Gtk_New_Hpaned (Pane);
      Pack_Start (Get_Vbox (Dialog), Pane, Expand => True, Fill => True);

      Gtk_New (Scrolled);
      Set_Policy (Scrolled, Policy_Automatic, Policy_Automatic);

      Gtk_New (Frame);
      Add (Frame, Scrolled);
      Pack1 (Pane, Frame, False, False);
      Add (Scrolled, Dialog.View);

      --  Right area

      Gtk_New_Vbox (Hbox, Homogeneous => False);

      Gtk_New (Frame);
      Add (Frame, Hbox);
      Pack2 (Pane, Frame, False, False);

      --  Name of current action

      Gtk_New (Event);
      Pack_Start (Hbox, Event, Expand => False);
      Color := Parse ("#0e79bd");
      --  ??? Should be shared with the preferences dialog and wizard
      Alloc (Get_Default_Colormap, Color);
      Set_Style (Event, Copy (Get_Style (Event)));
      Set_Background (Get_Style (Event), State_Normal, Color);

      Gtk_New (Dialog.Action_Name, "Current action");
      Set_Alignment (Dialog.Action_Name, 0.1, 0.5);
      Add (Event, Dialog.Action_Name);

      Gtk_New_Hseparator (Sep);
      Pack_Start (Hbox, Sep, Expand => False);

      --  Help on current action

      Gtk_New (Dialog.Help);
      Gtk_New (Scrolled);
      Pack_Start (Hbox, Scrolled, Expand => True, Fill => True);

      Set_Policy (Scrolled, Policy_Automatic, Policy_Automatic);
      Gtk_New (Text, Dialog.Help);
      Set_Wrap_Mode (Text, Wrap_Word);
      Add (Scrolled, Text);

      Gtk_New (Render);

      Gtk_New (Col);
      Num := Append_Column (Dialog.View, Col);
      Set_Title (Col, -"Action");
      Pack_Start (Col, Render, True);
      Add_Attribute (Col, Render, "text", 0);
      Set_Clickable (Col, True);
      Set_Resizable (Col, True);
      Set_Sort_Column_Id (Col, 0);
      Clicked (Col);

      Add_Menu (Dialog.Model,
                Set (Dialog.Model, -"Menus"),
                Glide_Window (Get_Main_Window (Ed.Kernel)).Menu_Bar,
                "<gps>/");

      Action_Iter := Start (Ed.Kernel);
      loop
         Action := Get (Action_Iter);
         exit when Action = No_Action;

         Parent := Find_Parent (Dialog.Model, Action.Context);
         if Parent = Null_Iter then
            if Action.Context = null then
               Parent := Set (Dialog.Model, -"General");
            else
               Parent := Set (Dialog.Model, Get_Name (Action.Context));
            end if;
         end if;

         Parent := Set (Dialog.Model, Get (Action_Iter), Parent);
         Next (Ed.Kernel, Action_Iter);
      end loop;

      Gtk_New_Hbox (Hbox, Homogeneous => False);
      Pack_Start (Get_Vbox (Dialog), Hbox, Expand => False);

      Gtk_New (Dialog.Grab);
      Set_Editable (Dialog.Grab, False);
      Pack_Start (Hbox, Dialog.Grab, Expand => True, Fill => True);

      Gtk_New (Grab, -"Grab");
      Pack_Start (Hbox, Grab, Expand => False);
      Widget_Callback.Object_Connect
        (Grab, "clicked",
         Widget_Callback.To_Marshaller (Add_Dialog_Grab'Access),
         Dialog);

      Button := Add_Button (Dialog, Stock_Ok, Gtk_Response_OK);
      Button := Add_Button (Dialog, Stock_Cancel, Gtk_Response_Cancel);

      Show_All (Dialog);

      while Run (Dialog) = Gtk_Response_OK loop
         declare
            Iter  : Gtk_Tree_Iter;
            Model : Gtk_Tree_Model;
            Result : Message_Dialog_Buttons;
            pragma Unreferenced (Result);
         begin
            Get_Selected (Get_Selection (Dialog.View), Model, Iter);

            if Iter /= Null_Iter
              and then Children (Model, Iter) = Null_Iter
              and then Get_Text (Dialog.Grab) /= ""
            then
               declare
                  Parent : constant String := Get_String
                    (Model, Gtk.Tree_Model.Parent (Model, Iter), 0);
                  S : constant String := Get_Text (Dialog.Grab);
               begin
                  if Parent = -Menu_Context_Name
                    and then Index (S, " ") /= 0
                  then
                     Result := Message_Dialog
                       (Msg => -"Menu shortcuts cannot use multiple keymaps",
                        Dialog_Type => Message_Dialog_Type'(Error),
                        Buttons     => Button_OK,
                        Title       => -"Invalid key shortcut",
                        Parent      => Gtk_Window (Dialog));
                  else
                     Iter := Set
                       (Ed.Model,
                        Parent => Find_Parent
                          (Gtk_Tree_Store (Ed.Model), Parent),
                        Descr   => Get_String (Model, Iter, 0),
                        Changed => True,
                        Key     => S);
                     exit;
                  end if;
               end;
            else
               exit;
            end if;
         end;
      end loop;

      Destroy (Dialog);

   exception
      when E : others =>
         Trace (Me, "Unexpected exception " & Exception_Information (E));
   end On_Add_Key;

   ------------------
   -- On_Edit_Keys --
   ------------------

   procedure On_Edit_Keys
     (Widget : access GObject_Record'Class; Kernel : Kernel_Handle)
   is
      Editor   : Keys_Editor;
      Scrolled : Gtk_Scrolled_Window;
      Bbox     : Gtk_Vbutton_Box;
      Box      : Gtk_Box;
      Button   : Gtk_Button;
      Col      : Gtk_Tree_View_Column;
      Render   : Gtk_Cell_Renderer_Text;
      Num      : Gint;
      Action   : Gtk_Widget;
      pragma Unreferenced (Widget, Num, Action);
   begin
      Editor := new Keys_Editor_Record;
      Initialize
        (Editor,
         Title  => -"Key shortcuts",
         Parent => Get_Main_Window (Kernel),
         Flags  => Destroy_With_Parent or Modal);
      Set_Default_Size (Editor, 640, 480);
      Editor.Kernel  := Kernel;

      Gtk_New_Hbox (Box, Homogeneous => False);
      Pack_Start (Get_Vbox (Editor), Box);

      Gtk_New (Scrolled);
      Set_Policy (Scrolled, Policy_Automatic, Policy_Automatic);
      Pack_Start (Box, Scrolled, Expand => True, Fill => True);

      Gtk_New (Bbox);
      Set_Layout (Bbox, Buttonbox_Start);
      Pack_Start (Box, Bbox, Expand => False);

      Gtk_New_From_Stock (Button, Stock_Add);
      Pack_Start (Bbox, Button);
      Widget_Callback.Object_Connect
        (Button, "clicked",
         Widget_Callback.To_Marshaller (On_Add_Key'Access),
         Editor);

      Gtk_New_From_Stock (Button, Stock_Remove);
      Pack_Start (Bbox, Button);
      Widget_Callback.Object_Connect
        (Button, "clicked",
         Widget_Callback.To_Marshaller (On_Remove_Key'Access),
         Editor);

      Gtk_New (Button, -"Grab");
      Pack_Start (Bbox, Button);
      Widget_Callback.Object_Connect
        (Button, "clicked",
         Widget_Callback.To_Marshaller (On_Grab_Key'Access),
         Editor);

      Gtk_New
        (Editor.Model,
         (Action_Column  => GType_String,
          Key_Column     => GType_String,
          Changed_Column => GType_Boolean));
      Gtk_New (Editor.View, Editor.Model);
      Add (Scrolled, Editor.View);

      Gtk_New (Render);

      Gtk_New (Col);
      Num := Append_Column (Editor.View, Col);
      Set_Title (Col, -"Action");
      Pack_Start (Col, Render, True);
      Add_Attribute (Col, Render, "text", Action_Column);
      Set_Clickable (Col, True);
      Set_Resizable (Col, True);
      Set_Sort_Column_Id (Col, Action_Column);

      Clicked (Col);

      Gtk_New (Col);
      Num := Append_Column (Editor.View, Col);
      Set_Title (Col, -"Shortcut");
      Pack_Start (Col, Render, False);
      Add_Attribute (Col, Render, "text", Key_Column);
      Set_Clickable (Col, True);
      Set_Resizable (Col, True);
      Set_Sort_Column_Id (Col, Key_Column);

      Fill_Editor (Editor);

      Action := Add_Button (Editor, Stock_Ok, Gtk_Response_OK);
      Action := Add_Button (Editor, Stock_Cancel, Gtk_Response_Cancel);

      Show_All (Editor);

      if Run (Editor) = Gtk_Response_OK then
         Save_Editor (Editor);
      end if;

      Destroy (Editor);
   end On_Edit_Keys;

   ---------------------
   -- Register_Module --
   ---------------------

   procedure Register_Module
     (Kernel : access Glide_Kernel.Kernel_Handle_Record'Class)
   is
      Manager : constant Key_Manager_Access := new Key_Manager_Record;
      Edit    : constant String := "/" & (-"Edit");
   begin
      Manager.Kernel := Kernel_Handle (Kernel);
      Load_Custom_Keys (Kernel, Manager);
      Set_Key_Handler (Kernel, Manager);

      Register_Menu
        (Kernel, Edit, -"_Key shortcuts",
         Ref_Item   => -"Preferences",
         Add_Before => False,
         Callback   => On_Edit_Keys'Access);
   end Register_Module;

end KeyManager_Module;
