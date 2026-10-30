// ==========================================================================
// pf-grid.dcl  --  PFSETUP's grid record dialog.
// V5's pfsetup_main (pfdialog.dcl), unchanged but for the title: Carlson-
// native file rows (named picker button LEFT, bound path RIGHT), OK / Cancel /
// Help at the bottom.  Name is the record's IDENTITY KEY -- picked files
// validate against it.  Scales are PLOT scales (e.g. 20 and 2).  The datum is
// typed here; the only command-line steps left are the two corner picks.
// ==========================================================================

pfsetup_main : dialog {
  label = "PFSETUP - Profile Grid";

  : boxed_column {
    label = "Identity";
    : popup_list {
      key         = "s_type";
      label       = "Utility Type";
      mnemonic    = "T";
      width       = 38;
      fixed_width = true;
    }
    : edit_box {
      key         = "s_name";
      label       = "Line Name";
      mnemonic    = "N";
      edit_limit  = 64;
      edit_width  = 18;
      width       = 38;
      fixed_width = true;
    }
    : popup_list {
      key         = "s_mat";
      label       = "Material";
      mnemonic    = "M";
      width       = 38;
      fixed_width = true;
    }
    : row {
      : edit_box {
        key         = "s_hs";
        label       = "Horizontal Scale";
        mnemonic    = "H";
        edit_limit  = 16;
        edit_width  = 8;
        width       = 30;
        fixed_width = true;
      }
      : edit_box {
        key         = "s_vs";
        label       = "Vertical Scale";
        mnemonic    = "V";
        edit_limit  = 16;
        edit_width  = 8;
        width       = 30;
        fixed_width = true;
      }
    }
  }
  spacer;

  : boxed_column {
    label = "Project Files";
    : row {
      : button { key = "s_cl_pick";   label = "Centerline";   width = 15; fixed_width = true; }
      : text   { key = "s_cl";   label = ""; width = 44; }
    }
    : row {
      : button { key = "s_inv_pick";  label = "Invert .pro";  width = 15; fixed_width = true; }
      : text   { key = "s_inv";  label = ""; width = 44; }
    }
    : row {
      : button { key = "s_top_pick";  label = "Crown .pro";   width = 15; fixed_width = true; }
      : text   { key = "s_top";  label = ""; width = 44; }
    }
    : row {
      : button { key = "s_tine_pick"; label = "Exist .tin";   width = 15; fixed_width = true; }
      : text   { key = "s_tine"; label = ""; width = 44; }
    }
    : row {
      : button { key = "s_tind_pick"; label = "Design .tin";  width = 15; fixed_width = true; }
      : text   { key = "s_tind"; label = ""; width = 44; }
    }
    : row {
      fixed_width = true;
      : button { key = "s_pro_clr"; label = "Clear Profiles"; width = 16; }
      : button { key = "s_tin_clr"; label = "Clear Surfaces"; width = 16; }
    }
  }
  spacer;

  : boxed_column {
    label = "Placement";
    : edit_box {
      key         = "s_datum";
      label       = "Datum Elevation";
      mnemonic    = "D";
      edit_limit  = 16;
      edit_width  = 10;
      width       = 38;
      fixed_width = true;
    }
    : toggle {
      key      = "s_repick";
      label    = "Re-pick grid extents on OK";
      mnemonic = "R";
    }
  }
  spacer;

  : text { label = "OK closes this dialog, then: pick grid LOWER-LEFT, then TOP-RIGHT."; }
  errtile;
  : row {
    fixed_width = true;
    alignment   = "centered";
    : button { key = "accept"; label = "OK";     mnemonic = "O"; width = 11; is_default = true; }
    : button { key = "cancel"; label = "Cancel"; mnemonic = "C"; width = 11; is_cancel  = true; }
    : button { key = "help";   label = "Help";   width = 11; }
  }
}
