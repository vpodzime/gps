-----------------------------------------------------------------------
--                               G P S                               --
--                                                                   --
--                        Copyright (C) 2001-2003                    --
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

with Glide_Kernel.Modules; use Glide_Kernel.Modules;
with Glide_Kernel.Scripts; use Glide_Kernel.Scripts;
with Basic_Types;          use Basic_Types;
with GNAT.OS_Lib;          use GNAT.OS_Lib;
with Diff_Utils2;          use Diff_Utils2;
with Vdiff2_Utils;         use Vdiff2_Utils;

package body Vdiff2_Command is

   use Diff_Head_List;
   use Diff_Chunk_List;

   ------------
   -- Create --
   ------------

   procedure Create
     (Item      : out Diff_Command_Access;
      Kernel    : Kernel_Handle;
      List_Diff : Diff_Head_List_Access;
      Action    : Handler_Action) is

   begin
      Item           := new Diff_Command;
      Item.Kernel    := Kernel;
      Item.List_Diff := List_Diff;
      Item.Action    := Action;
   end Create;

   -------------------------
   --  Unchecked_Execute  --
   -------------------------

   procedure Unchecked_Execute
     (Command : access Diff_Command;
      Diff    : in out Diff_Head_List.List_Node)
   is
      Tmp : Diff_Head_Access := new Diff_Head;
   begin
      if Diff /= Diff_Head_List.Null_Node then
         Tmp.all := Data (Diff);
         Command.Action (Command.Kernel, Tmp);
      end if;
      Free (Tmp);
   end Unchecked_Execute;

   -------------
   -- Execute --
   -------------

   function Execute
     (Command : access Diff_Command)
      return Command_Return_Type
   is
      Context       : constant Selection_Context_Access
        := Get_Current_Context (Command.Kernel);
      Curr_Node     : Diff_Head_List.List_Node;
      Diff          : Diff_Head_Access := new Diff_Head;
      Selected_File : GNAT.OS_Lib.String_Access;

   begin
      if Has_File_Information (File_Selection_Context_Access (Context))
        and then
          Has_Directory_Information (File_Selection_Context_Access (Context))
      then
         Selected_File := new String'
           (Directory_Information (File_Selection_Context_Access (Context)) &
            File_Information (File_Selection_Context_Access (Context)));

         Curr_Node := Is_In_Diff_List (Selected_File, Command.List_Diff.all);

         if Curr_Node /= Diff_Head_List.Null_Node then
            Diff.all := Data (Curr_Node);
            Command.Action (Command.Kernel, Diff);
            if Diff /= null then
               Set_Data (Curr_Node, Diff.all);
            else
               Remove_Nodes (Command.List_Diff.all,
                             Prev (Command.List_Diff.all, Curr_Node),
                             Curr_Node);
            end if;
            Free (Selected_File);
            Free (Diff);
         end if;
      end if;
      return Commands.Success;
   exception
      when others =>
         return Failure;
   end Execute;

   ---------------------
   -- Is_In_Diff_List --
   ---------------------

   function Is_In_Diff_List
     (Selected_File : GNAT.OS_Lib.String_Access;
      List          : Diff_Head_List.List) return Diff_Head_List.List_Node
   is
      Curr_Node : Diff_Head_List.List_Node := First (List);
      Diff      : Diff_Head;
   begin
      while Curr_Node /= Diff_Head_List.Null_Node loop
         Diff := Data (Curr_Node);
         exit when (Diff.File1 /= null
                    and then Diff.File1.all = Selected_File.all)
           or else (Diff.File2 /= null
                    and then Diff.File2.all = Selected_File.all)
           or else (Diff.File3 /= null
                    and then Diff.File3.all = Selected_File.all);
         Curr_Node := Next (Curr_Node);
      end loop;

      return Curr_Node;
   end Is_In_Diff_List;

   ---------------------
   -- Next_Difference --
   ---------------------

   procedure Next_Difference
     (Kernel : Kernel_Handle;
      Diff   : in out  Diff_Head_Access)
   is
      Link      : Diff_List_Node;
      Curr_Data : Diff_Chunk_Access;
   begin
      if Next (Diff.Current_Node) /= Diff_Chunk_List.Null_Node then
         Diff.Current_Node := Next (Diff.Current_Node);
         Link := Diff.Current_Node;
         Curr_Data := Data (Link);
         Goto_Difference (Kernel, Curr_Data);
      end if;
   end Next_Difference;

   ---------------------
   -- Prev_Difference --
   ---------------------

   procedure Prev_Difference
     (Kernel : Kernel_Handle;
      Diff   : in out Diff_Head_Access)
   is
      Link      : Diff_List_Node;
      Curr_Data : Diff_Chunk_Access;
   begin
      Link := Prev (Diff.List, Diff.Current_Node);
      if  Link /= Diff_Chunk_List.Null_Node then
         Diff.Current_Node := Link;
         Curr_Data := Data (Link);
         Goto_Difference (Kernel, Curr_Data);
      end if;
   end Prev_Difference;

   ---------------------
   -- First_Diference --
   ---------------------

   procedure First_Difference
     (Kernel : Kernel_Handle;
      Diff   : in out Diff_Head_Access)
   is
      Link      : Diff_List_Node;
      Curr_Data : Diff_Chunk_Access;
   begin
      if Diff.Current_Node /= Last (Diff.List) then
         Diff.Current_Node := First (Diff.List);
         Link := Diff.Current_Node;
         Curr_Data := Data (Link);
         Goto_Difference (Kernel, Curr_Data);
      end if;
   end First_Difference;

   --------------------
   -- Last_Diference --
   --------------------

   procedure Last_Difference
     (Kernel : Kernel_Handle;
      Diff   : in out Diff_Head_Access)
   is
      Link     : Diff_List_Node;
      Curr_Data : Diff_Chunk_Access;
   begin
      if Diff.Current_Node /= Last (Diff.List) then
         Diff.Current_Node := Last (Diff.List);
         Link := Diff.Current_Node;
         Curr_Data := Data (Link);
         Goto_Difference (Kernel, Curr_Data);
      end if;
   end Last_Difference;

   -----------------------
   -- Reload_Difference --
   -----------------------

   procedure Reload_Difference
     (Kernel : Kernel_Handle;
      Diff   : in out Diff_Head_Access) is
   begin
      Unhighlight_Difference (Kernel, Diff);
      Free (Diff.List);
      Diff.List := Diff3
        (Kernel, Diff.File1.all,
         Diff.File2.all, Diff.File3.all);
      Diff.Current_Node := First (Diff.List);
      Show_Differences3 (Kernel, Diff.all);
   end Reload_Difference;


   ----------------------
   -- Close_Difference --
   ----------------------

   procedure Close_Difference
     (Kernel : Kernel_Handle;
      Diff   : in out Diff_Head_Access)
   is
      Args1 : Argument_List := (1 => Diff.File1);
      Args2 : Argument_List := (1 => Diff.File2);
      Args3 : Argument_List := (1 => Diff.File3);

   begin
      Execute_GPS_Shell_Command (Kernel, "close", Args1);

      if Args2 (1) /= null then
         Execute_GPS_Shell_Command (Kernel, "close", Args2);
      end if;

      if Args3 (1) /= null then
         Execute_GPS_Shell_Command (Kernel, "close", Args3);
      end if;
   end Close_Difference;

   ----------------------------
   -- Unhighlight_Difference --
   ----------------------------

   procedure Unhighlight_Difference
     (Kernel : Kernel_Handle;
      Diff   : in out Diff_Head_Access)is
   begin
      Hide_Differences (Kernel, Diff.all);
   end Unhighlight_Difference;

   --------------------
   -- Goto_Difference --
   --------------------

   procedure Goto_Difference
     (Kernel : Kernel_Handle;
      Link : Diff_Chunk_Access)
   is
      Args : Argument_List (1 .. 1);
   begin

      if Link.Range1.Mark /= null
        and then Link.Range2.Mark /= null then
         Args := (1 => new String'(Link.Range1.Mark.all));
         Execute_GPS_Shell_Command (Kernel, "goto_mark", Args);
         Basic_Types.Free (Args);

         Args := (1 => new String'(Link.Range2.Mark.all));
         Execute_GPS_Shell_Command (Kernel, "goto_mark", Args);
         Basic_Types.Free (Args);
         if Link.Range3.Mark /= null then
            Args := (1 => new String'(Link.Range3.Mark.all));
            Execute_GPS_Shell_Command (Kernel, "goto_mark", Args);
            Basic_Types.Free (Args);
         end if;
      end if;
   end Goto_Difference;

   -----------------------
   -- Remove_Difference --
   -----------------------

   procedure Remove_Difference
     (Kernel : Kernel_Handle;
      Diff   : in out Diff_Head_Access) is
   begin
      Unhighlight_Difference (Kernel, Diff);
      Free (Diff.List);
   end Remove_Difference;

   ---------------------
   -- Change_Ref_File --
   ---------------------

   procedure Change_Ref_File
     (Kernel : Kernel_Handle;
      Diff   : in out Diff_Head_Access) is
   begin
      Unhighlight_Difference (Kernel, Diff);
      Show_Differences3 (Kernel, Diff.all);
   end Change_Ref_File;

end Vdiff2_Command;

