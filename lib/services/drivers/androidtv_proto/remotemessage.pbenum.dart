// This is a generated file - do not edit.
//
// Generated from remotemessage.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class RemoteKeyCode extends $pb.ProtobufEnum {
  /// Unknown key code.
  static const RemoteKeyCode KEYCODE_UNKNOWN =
      RemoteKeyCode._(0, _omitEnumNames ? '' : 'KEYCODE_UNKNOWN');

  /// Soft Left key.
  /// Usually situated below the display on phones and used as a multi-function
  /// feature key for selecting a software defined function shown on the bottom left
  /// of the display.
  static const RemoteKeyCode KEYCODE_SOFT_LEFT =
      RemoteKeyCode._(1, _omitEnumNames ? '' : 'KEYCODE_SOFT_LEFT');

  /// Soft Right key.
  /// Usually situated below the display on phones and used as a multi-function
  /// feature key for selecting a software defined function shown on the bottom right
  /// of the display.
  static const RemoteKeyCode KEYCODE_SOFT_RIGHT =
      RemoteKeyCode._(2, _omitEnumNames ? '' : 'KEYCODE_SOFT_RIGHT');

  /// Home key.
  /// This key is handled by the framework and is never delivered to applications.
  static const RemoteKeyCode KEYCODE_HOME =
      RemoteKeyCode._(3, _omitEnumNames ? '' : 'KEYCODE_HOME');

  /// Back key.
  static const RemoteKeyCode KEYCODE_BACK =
      RemoteKeyCode._(4, _omitEnumNames ? '' : 'KEYCODE_BACK');

  /// Call key.
  static const RemoteKeyCode KEYCODE_CALL =
      RemoteKeyCode._(5, _omitEnumNames ? '' : 'KEYCODE_CALL');

  /// End Call key.
  static const RemoteKeyCode KEYCODE_ENDCALL =
      RemoteKeyCode._(6, _omitEnumNames ? '' : 'KEYCODE_ENDCALL');

  /// '0' key.
  static const RemoteKeyCode KEYCODE_0 =
      RemoteKeyCode._(7, _omitEnumNames ? '' : 'KEYCODE_0');

  /// '1' key.
  static const RemoteKeyCode KEYCODE_1 =
      RemoteKeyCode._(8, _omitEnumNames ? '' : 'KEYCODE_1');

  /// '2' key.
  static const RemoteKeyCode KEYCODE_2 =
      RemoteKeyCode._(9, _omitEnumNames ? '' : 'KEYCODE_2');

  /// '3' key.
  static const RemoteKeyCode KEYCODE_3 =
      RemoteKeyCode._(10, _omitEnumNames ? '' : 'KEYCODE_3');

  /// '4' key.
  static const RemoteKeyCode KEYCODE_4 =
      RemoteKeyCode._(11, _omitEnumNames ? '' : 'KEYCODE_4');

  /// '5' key.
  static const RemoteKeyCode KEYCODE_5 =
      RemoteKeyCode._(12, _omitEnumNames ? '' : 'KEYCODE_5');

  /// '6' key.
  static const RemoteKeyCode KEYCODE_6 =
      RemoteKeyCode._(13, _omitEnumNames ? '' : 'KEYCODE_6');

  /// '7' key.
  static const RemoteKeyCode KEYCODE_7 =
      RemoteKeyCode._(14, _omitEnumNames ? '' : 'KEYCODE_7');

  /// '8' key.
  static const RemoteKeyCode KEYCODE_8 =
      RemoteKeyCode._(15, _omitEnumNames ? '' : 'KEYCODE_8');

  /// '9' key.
  static const RemoteKeyCode KEYCODE_9 =
      RemoteKeyCode._(16, _omitEnumNames ? '' : 'KEYCODE_9');

  /// '*' key.
  static const RemoteKeyCode KEYCODE_STAR =
      RemoteKeyCode._(17, _omitEnumNames ? '' : 'KEYCODE_STAR');

  /// '#' key.
  static const RemoteKeyCode KEYCODE_POUND =
      RemoteKeyCode._(18, _omitEnumNames ? '' : 'KEYCODE_POUND');

  /// Directional Pad Up key.
  /// May also be synthesized from trackball motions.
  static const RemoteKeyCode KEYCODE_DPAD_UP =
      RemoteKeyCode._(19, _omitEnumNames ? '' : 'KEYCODE_DPAD_UP');

  /// Directional Pad Down key.
  /// May also be synthesized from trackball motions.
  static const RemoteKeyCode KEYCODE_DPAD_DOWN =
      RemoteKeyCode._(20, _omitEnumNames ? '' : 'KEYCODE_DPAD_DOWN');

  /// Directional Pad Left key.
  /// May also be synthesized from trackball motions.
  static const RemoteKeyCode KEYCODE_DPAD_LEFT =
      RemoteKeyCode._(21, _omitEnumNames ? '' : 'KEYCODE_DPAD_LEFT');

  /// Directional Pad Right key.
  /// May also be synthesized from trackball motions.
  static const RemoteKeyCode KEYCODE_DPAD_RIGHT =
      RemoteKeyCode._(22, _omitEnumNames ? '' : 'KEYCODE_DPAD_RIGHT');

  /// Directional Pad Center key.
  /// May also be synthesized from trackball motions.
  static const RemoteKeyCode KEYCODE_DPAD_CENTER =
      RemoteKeyCode._(23, _omitEnumNames ? '' : 'KEYCODE_DPAD_CENTER');

  /// Volume Up key.
  /// Adjusts the speaker volume up.
  static const RemoteKeyCode KEYCODE_VOLUME_UP =
      RemoteKeyCode._(24, _omitEnumNames ? '' : 'KEYCODE_VOLUME_UP');

  /// Volume Down key.
  /// Adjusts the speaker volume down.
  static const RemoteKeyCode KEYCODE_VOLUME_DOWN =
      RemoteKeyCode._(25, _omitEnumNames ? '' : 'KEYCODE_VOLUME_DOWN');

  /// Power key.
  static const RemoteKeyCode KEYCODE_POWER =
      RemoteKeyCode._(26, _omitEnumNames ? '' : 'KEYCODE_POWER');

  /// Camera key.
  /// Used to launch a camera application or take pictures.
  static const RemoteKeyCode KEYCODE_CAMERA =
      RemoteKeyCode._(27, _omitEnumNames ? '' : 'KEYCODE_CAMERA');

  /// Clear key.
  static const RemoteKeyCode KEYCODE_CLEAR =
      RemoteKeyCode._(28, _omitEnumNames ? '' : 'KEYCODE_CLEAR');

  /// 'A' key.
  static const RemoteKeyCode KEYCODE_A =
      RemoteKeyCode._(29, _omitEnumNames ? '' : 'KEYCODE_A');

  /// 'B' key.
  static const RemoteKeyCode KEYCODE_B =
      RemoteKeyCode._(30, _omitEnumNames ? '' : 'KEYCODE_B');

  /// 'C' key.
  static const RemoteKeyCode KEYCODE_C =
      RemoteKeyCode._(31, _omitEnumNames ? '' : 'KEYCODE_C');

  /// 'D' key.
  static const RemoteKeyCode KEYCODE_D =
      RemoteKeyCode._(32, _omitEnumNames ? '' : 'KEYCODE_D');

  /// 'E' key.
  static const RemoteKeyCode KEYCODE_E =
      RemoteKeyCode._(33, _omitEnumNames ? '' : 'KEYCODE_E');

  /// 'F' key.
  static const RemoteKeyCode KEYCODE_F =
      RemoteKeyCode._(34, _omitEnumNames ? '' : 'KEYCODE_F');

  /// 'G' key.
  static const RemoteKeyCode KEYCODE_G =
      RemoteKeyCode._(35, _omitEnumNames ? '' : 'KEYCODE_G');

  /// 'H' key.
  static const RemoteKeyCode KEYCODE_H =
      RemoteKeyCode._(36, _omitEnumNames ? '' : 'KEYCODE_H');

  /// 'I' key.
  static const RemoteKeyCode KEYCODE_I =
      RemoteKeyCode._(37, _omitEnumNames ? '' : 'KEYCODE_I');

  /// 'J' key.
  static const RemoteKeyCode KEYCODE_J =
      RemoteKeyCode._(38, _omitEnumNames ? '' : 'KEYCODE_J');

  /// 'K' key.
  static const RemoteKeyCode KEYCODE_K =
      RemoteKeyCode._(39, _omitEnumNames ? '' : 'KEYCODE_K');

  /// 'L' key.
  static const RemoteKeyCode KEYCODE_L =
      RemoteKeyCode._(40, _omitEnumNames ? '' : 'KEYCODE_L');

  /// 'M' key.
  static const RemoteKeyCode KEYCODE_M =
      RemoteKeyCode._(41, _omitEnumNames ? '' : 'KEYCODE_M');

  /// 'N' key.
  static const RemoteKeyCode KEYCODE_N =
      RemoteKeyCode._(42, _omitEnumNames ? '' : 'KEYCODE_N');

  /// 'O' key.
  static const RemoteKeyCode KEYCODE_O =
      RemoteKeyCode._(43, _omitEnumNames ? '' : 'KEYCODE_O');

  /// 'P' key.
  static const RemoteKeyCode KEYCODE_P =
      RemoteKeyCode._(44, _omitEnumNames ? '' : 'KEYCODE_P');

  /// 'Q' key.
  static const RemoteKeyCode KEYCODE_Q =
      RemoteKeyCode._(45, _omitEnumNames ? '' : 'KEYCODE_Q');

  /// 'R' key.
  static const RemoteKeyCode KEYCODE_R =
      RemoteKeyCode._(46, _omitEnumNames ? '' : 'KEYCODE_R');

  /// 'S' key.
  static const RemoteKeyCode KEYCODE_S =
      RemoteKeyCode._(47, _omitEnumNames ? '' : 'KEYCODE_S');

  /// 'T' key.
  static const RemoteKeyCode KEYCODE_T =
      RemoteKeyCode._(48, _omitEnumNames ? '' : 'KEYCODE_T');

  /// 'U' key.
  static const RemoteKeyCode KEYCODE_U =
      RemoteKeyCode._(49, _omitEnumNames ? '' : 'KEYCODE_U');

  /// 'V' key.
  static const RemoteKeyCode KEYCODE_V =
      RemoteKeyCode._(50, _omitEnumNames ? '' : 'KEYCODE_V');

  /// 'W' key.
  static const RemoteKeyCode KEYCODE_W =
      RemoteKeyCode._(51, _omitEnumNames ? '' : 'KEYCODE_W');

  /// 'X' key.
  static const RemoteKeyCode KEYCODE_X =
      RemoteKeyCode._(52, _omitEnumNames ? '' : 'KEYCODE_X');

  /// 'Y' key.
  static const RemoteKeyCode KEYCODE_Y =
      RemoteKeyCode._(53, _omitEnumNames ? '' : 'KEYCODE_Y');

  /// 'Z' key.
  static const RemoteKeyCode KEYCODE_Z =
      RemoteKeyCode._(54, _omitEnumNames ? '' : 'KEYCODE_Z');

  /// ',' key.
  static const RemoteKeyCode KEYCODE_COMMA =
      RemoteKeyCode._(55, _omitEnumNames ? '' : 'KEYCODE_COMMA');

  /// '.' key.
  static const RemoteKeyCode KEYCODE_PERIOD =
      RemoteKeyCode._(56, _omitEnumNames ? '' : 'KEYCODE_PERIOD');

  /// Left Alt modifier key.
  static const RemoteKeyCode KEYCODE_ALT_LEFT =
      RemoteKeyCode._(57, _omitEnumNames ? '' : 'KEYCODE_ALT_LEFT');

  /// Right Alt modifier key.
  static const RemoteKeyCode KEYCODE_ALT_RIGHT =
      RemoteKeyCode._(58, _omitEnumNames ? '' : 'KEYCODE_ALT_RIGHT');

  /// Left Shift modifier key.
  static const RemoteKeyCode KEYCODE_SHIFT_LEFT =
      RemoteKeyCode._(59, _omitEnumNames ? '' : 'KEYCODE_SHIFT_LEFT');

  /// Right Shift modifier key.
  static const RemoteKeyCode KEYCODE_SHIFT_RIGHT =
      RemoteKeyCode._(60, _omitEnumNames ? '' : 'KEYCODE_SHIFT_RIGHT');

  /// Tab key.
  static const RemoteKeyCode KEYCODE_TAB =
      RemoteKeyCode._(61, _omitEnumNames ? '' : 'KEYCODE_TAB');

  /// Space key.
  static const RemoteKeyCode KEYCODE_SPACE =
      RemoteKeyCode._(62, _omitEnumNames ? '' : 'KEYCODE_SPACE');

  /// Symbol modifier key.
  /// Used to enter alternate symbols.
  static const RemoteKeyCode KEYCODE_SYM =
      RemoteKeyCode._(63, _omitEnumNames ? '' : 'KEYCODE_SYM');

  /// Explorer special function key.
  /// Used to launch a browser application.
  static const RemoteKeyCode KEYCODE_EXPLORER =
      RemoteKeyCode._(64, _omitEnumNames ? '' : 'KEYCODE_EXPLORER');

  /// Envelope special function key.
  /// Used to launch a mail application.
  static const RemoteKeyCode KEYCODE_ENVELOPE =
      RemoteKeyCode._(65, _omitEnumNames ? '' : 'KEYCODE_ENVELOPE');

  /// Enter key.
  static const RemoteKeyCode KEYCODE_ENTER =
      RemoteKeyCode._(66, _omitEnumNames ? '' : 'KEYCODE_ENTER');

  /// Backspace key.
  /// Deletes characters before the insertion point, unlike KEYCODE_FORWARD_DEL.
  static const RemoteKeyCode KEYCODE_DEL =
      RemoteKeyCode._(67, _omitEnumNames ? '' : 'KEYCODE_DEL');

  /// '`' (backtick) key.
  static const RemoteKeyCode KEYCODE_GRAVE =
      RemoteKeyCode._(68, _omitEnumNames ? '' : 'KEYCODE_GRAVE');

  /// '-'.
  static const RemoteKeyCode KEYCODE_MINUS =
      RemoteKeyCode._(69, _omitEnumNames ? '' : 'KEYCODE_MINUS');

  /// '=' key.
  static const RemoteKeyCode KEYCODE_EQUALS =
      RemoteKeyCode._(70, _omitEnumNames ? '' : 'KEYCODE_EQUALS');

  /// '[' key.
  static const RemoteKeyCode KEYCODE_LEFT_BRACKET =
      RemoteKeyCode._(71, _omitEnumNames ? '' : 'KEYCODE_LEFT_BRACKET');

  /// ']' key.
  static const RemoteKeyCode KEYCODE_RIGHT_BRACKET =
      RemoteKeyCode._(72, _omitEnumNames ? '' : 'KEYCODE_RIGHT_BRACKET');

  /// '\' key.
  static const RemoteKeyCode KEYCODE_BACKSLASH =
      RemoteKeyCode._(73, _omitEnumNames ? '' : 'KEYCODE_BACKSLASH');

  /// ';' key.
  static const RemoteKeyCode KEYCODE_SEMICOLON =
      RemoteKeyCode._(74, _omitEnumNames ? '' : 'KEYCODE_SEMICOLON');

  /// ''' (apostrophe) key.
  static const RemoteKeyCode KEYCODE_APOSTROPHE =
      RemoteKeyCode._(75, _omitEnumNames ? '' : 'KEYCODE_APOSTROPHE');

  /// '/' key.
  static const RemoteKeyCode KEYCODE_SLASH =
      RemoteKeyCode._(76, _omitEnumNames ? '' : 'KEYCODE_SLASH');

  /// '@' key.
  static const RemoteKeyCode KEYCODE_AT =
      RemoteKeyCode._(77, _omitEnumNames ? '' : 'KEYCODE_AT');

  /// Number modifier key.
  /// Used to enter numeric symbols.
  /// This key is not KEYCODE_NUM_LOCK; it is more like KEYCODE_ALT_LEFT.
  static const RemoteKeyCode KEYCODE_NUM =
      RemoteKeyCode._(78, _omitEnumNames ? '' : 'KEYCODE_NUM');

  /// Headset Hook key.
  /// Used to hang up calls and stop media.
  static const RemoteKeyCode KEYCODE_HEADSETHOOK =
      RemoteKeyCode._(79, _omitEnumNames ? '' : 'KEYCODE_HEADSETHOOK');

  /// Camera Focus key.
  /// Used to focus the camera.
  static const RemoteKeyCode KEYCODE_FOCUS =
      RemoteKeyCode._(80, _omitEnumNames ? '' : 'KEYCODE_FOCUS');

  /// '+' key.
  static const RemoteKeyCode KEYCODE_PLUS =
      RemoteKeyCode._(81, _omitEnumNames ? '' : 'KEYCODE_PLUS');

  /// Menu key.
  static const RemoteKeyCode KEYCODE_MENU =
      RemoteKeyCode._(82, _omitEnumNames ? '' : 'KEYCODE_MENU');

  /// Notification key.
  static const RemoteKeyCode KEYCODE_NOTIFICATION =
      RemoteKeyCode._(83, _omitEnumNames ? '' : 'KEYCODE_NOTIFICATION');

  /// Search key.
  static const RemoteKeyCode KEYCODE_SEARCH =
      RemoteKeyCode._(84, _omitEnumNames ? '' : 'KEYCODE_SEARCH');

  /// Play/Pause media key.
  static const RemoteKeyCode KEYCODE_MEDIA_PLAY_PAUSE =
      RemoteKeyCode._(85, _omitEnumNames ? '' : 'KEYCODE_MEDIA_PLAY_PAUSE');

  /// Stop media key.
  static const RemoteKeyCode KEYCODE_MEDIA_STOP =
      RemoteKeyCode._(86, _omitEnumNames ? '' : 'KEYCODE_MEDIA_STOP');

  /// Play Next media key.
  static const RemoteKeyCode KEYCODE_MEDIA_NEXT =
      RemoteKeyCode._(87, _omitEnumNames ? '' : 'KEYCODE_MEDIA_NEXT');

  /// Play Previous media key.
  static const RemoteKeyCode KEYCODE_MEDIA_PREVIOUS =
      RemoteKeyCode._(88, _omitEnumNames ? '' : 'KEYCODE_MEDIA_PREVIOUS');

  /// Rewind media key.
  static const RemoteKeyCode KEYCODE_MEDIA_REWIND =
      RemoteKeyCode._(89, _omitEnumNames ? '' : 'KEYCODE_MEDIA_REWIND');

  /// Fast Forward media key.
  static const RemoteKeyCode KEYCODE_MEDIA_FAST_FORWARD =
      RemoteKeyCode._(90, _omitEnumNames ? '' : 'KEYCODE_MEDIA_FAST_FORWARD');

  /// Mute key.
  /// Mutes the microphone, unlike KEYCODE_VOLUME_MUTE.
  static const RemoteKeyCode KEYCODE_MUTE =
      RemoteKeyCode._(91, _omitEnumNames ? '' : 'KEYCODE_MUTE');

  /// Page Up key.
  static const RemoteKeyCode KEYCODE_PAGE_UP =
      RemoteKeyCode._(92, _omitEnumNames ? '' : 'KEYCODE_PAGE_UP');

  /// Page Down key.
  static const RemoteKeyCode KEYCODE_PAGE_DOWN =
      RemoteKeyCode._(93, _omitEnumNames ? '' : 'KEYCODE_PAGE_DOWN');

  /// Picture Symbols modifier key.
  /// Used to switch symbol sets (Emoji, Kao-moji).
  static const RemoteKeyCode KEYCODE_PICTSYMBOLS =
      RemoteKeyCode._(94, _omitEnumNames ? '' : 'KEYCODE_PICTSYMBOLS');

  /// Switch Charset modifier key.
  /// Used to switch character sets (Kanji, Katakana).
  static const RemoteKeyCode KEYCODE_SWITCH_CHARSET =
      RemoteKeyCode._(95, _omitEnumNames ? '' : 'KEYCODE_SWITCH_CHARSET');

  /// A Button key.
  /// On a game controller, the A button should be either the button labeled A
  /// or the first button on the bottom row of controller buttons.
  static const RemoteKeyCode KEYCODE_BUTTON_A =
      RemoteKeyCode._(96, _omitEnumNames ? '' : 'KEYCODE_BUTTON_A');

  /// B Button key.
  /// On a game controller, the B button should be either the button labeled B
  /// or the second button on the bottom row of controller buttons.
  static const RemoteKeyCode KEYCODE_BUTTON_B =
      RemoteKeyCode._(97, _omitEnumNames ? '' : 'KEYCODE_BUTTON_B');

  /// C Button key.
  /// On a game controller, the C button should be either the button labeled C
  /// or the third button on the bottom row of controller buttons.
  static const RemoteKeyCode KEYCODE_BUTTON_C =
      RemoteKeyCode._(98, _omitEnumNames ? '' : 'KEYCODE_BUTTON_C');

  /// X Button key.
  /// On a game controller, the X button should be either the button labeled X
  /// or the first button on the upper row of controller buttons.
  static const RemoteKeyCode KEYCODE_BUTTON_X =
      RemoteKeyCode._(99, _omitEnumNames ? '' : 'KEYCODE_BUTTON_X');

  /// Y Button key.
  /// On a game controller, the Y button should be either the button labeled Y
  /// or the second button on the upper row of controller buttons.
  static const RemoteKeyCode KEYCODE_BUTTON_Y =
      RemoteKeyCode._(100, _omitEnumNames ? '' : 'KEYCODE_BUTTON_Y');

  /// Z Button key.
  /// On a game controller, the Z button should be either the button labeled Z
  /// or the third button on the upper row of controller buttons.
  static const RemoteKeyCode KEYCODE_BUTTON_Z =
      RemoteKeyCode._(101, _omitEnumNames ? '' : 'KEYCODE_BUTTON_Z');

  /// L1 Button key.
  /// On a game controller, the L1 button should be either the button labeled L1 (or L)
  /// or the top left trigger button.
  static const RemoteKeyCode KEYCODE_BUTTON_L1 =
      RemoteKeyCode._(102, _omitEnumNames ? '' : 'KEYCODE_BUTTON_L1');

  /// R1 Button key.
  /// On a game controller, the R1 button should be either the button labeled R1 (or R)
  /// or the top right trigger button.
  static const RemoteKeyCode KEYCODE_BUTTON_R1 =
      RemoteKeyCode._(103, _omitEnumNames ? '' : 'KEYCODE_BUTTON_R1');

  /// L2 Button key.
  /// On a game controller, the L2 button should be either the button labeled L2
  /// or the bottom left trigger button.
  static const RemoteKeyCode KEYCODE_BUTTON_L2 =
      RemoteKeyCode._(104, _omitEnumNames ? '' : 'KEYCODE_BUTTON_L2');

  /// R2 Button key.
  /// On a game controller, the R2 button should be either the button labeled R2
  /// or the bottom right trigger button.
  static const RemoteKeyCode KEYCODE_BUTTON_R2 =
      RemoteKeyCode._(105, _omitEnumNames ? '' : 'KEYCODE_BUTTON_R2');

  /// Left Thumb Button key.
  /// On a game controller, the left thumb button indicates that the left (or only)
  /// joystick is pressed.
  static const RemoteKeyCode KEYCODE_BUTTON_THUMBL =
      RemoteKeyCode._(106, _omitEnumNames ? '' : 'KEYCODE_BUTTON_THUMBL');

  /// Right Thumb Button key.
  /// On a game controller, the right thumb button indicates that the right
  /// joystick is pressed.
  static const RemoteKeyCode KEYCODE_BUTTON_THUMBR =
      RemoteKeyCode._(107, _omitEnumNames ? '' : 'KEYCODE_BUTTON_THUMBR');

  /// Start Button key.
  /// On a game controller, the button labeled Start.
  static const RemoteKeyCode KEYCODE_BUTTON_START =
      RemoteKeyCode._(108, _omitEnumNames ? '' : 'KEYCODE_BUTTON_START');

  /// Select Button key.
  /// On a game controller, the button labeled Select.
  static const RemoteKeyCode KEYCODE_BUTTON_SELECT =
      RemoteKeyCode._(109, _omitEnumNames ? '' : 'KEYCODE_BUTTON_SELECT');

  /// Mode Button key.
  /// On a game controller, the button labeled Mode.
  static const RemoteKeyCode KEYCODE_BUTTON_MODE =
      RemoteKeyCode._(110, _omitEnumNames ? '' : 'KEYCODE_BUTTON_MODE');

  /// Escape key.
  static const RemoteKeyCode KEYCODE_ESCAPE =
      RemoteKeyCode._(111, _omitEnumNames ? '' : 'KEYCODE_ESCAPE');

  /// Forward Delete key.
  /// Deletes characters ahead of the insertion point, unlike KEYCODE_DEL.
  static const RemoteKeyCode KEYCODE_FORWARD_DEL =
      RemoteKeyCode._(112, _omitEnumNames ? '' : 'KEYCODE_FORWARD_DEL');

  /// Left Control modifier key.
  static const RemoteKeyCode KEYCODE_CTRL_LEFT =
      RemoteKeyCode._(113, _omitEnumNames ? '' : 'KEYCODE_CTRL_LEFT');

  /// Right Control modifier key.
  static const RemoteKeyCode KEYCODE_CTRL_RIGHT =
      RemoteKeyCode._(114, _omitEnumNames ? '' : 'KEYCODE_CTRL_RIGHT');

  /// Caps Lock key.
  static const RemoteKeyCode KEYCODE_CAPS_LOCK =
      RemoteKeyCode._(115, _omitEnumNames ? '' : 'KEYCODE_CAPS_LOCK');

  /// Scroll Lock key.
  static const RemoteKeyCode KEYCODE_SCROLL_LOCK =
      RemoteKeyCode._(116, _omitEnumNames ? '' : 'KEYCODE_SCROLL_LOCK');

  /// Left Meta modifier key.
  static const RemoteKeyCode KEYCODE_META_LEFT =
      RemoteKeyCode._(117, _omitEnumNames ? '' : 'KEYCODE_META_LEFT');

  /// Right Meta modifier key.
  static const RemoteKeyCode KEYCODE_META_RIGHT =
      RemoteKeyCode._(118, _omitEnumNames ? '' : 'KEYCODE_META_RIGHT');

  /// Function modifier key.
  static const RemoteKeyCode KEYCODE_FUNCTION =
      RemoteKeyCode._(119, _omitEnumNames ? '' : 'KEYCODE_FUNCTION');

  /// System Request / Print Screen key.
  static const RemoteKeyCode KEYCODE_SYSRQ =
      RemoteKeyCode._(120, _omitEnumNames ? '' : 'KEYCODE_SYSRQ');

  /// Break / Pause key.
  static const RemoteKeyCode KEYCODE_BREAK =
      RemoteKeyCode._(121, _omitEnumNames ? '' : 'KEYCODE_BREAK');

  /// Home Movement key.
  /// Used for scrolling or moving the cursor around to the start of a line
  /// or to the top of a list.
  static const RemoteKeyCode KEYCODE_MOVE_HOME =
      RemoteKeyCode._(122, _omitEnumNames ? '' : 'KEYCODE_MOVE_HOME');

  /// End Movement key.
  /// Used for scrolling or moving the cursor around to the end of a line
  /// or to the bottom of a list.
  static const RemoteKeyCode KEYCODE_MOVE_END =
      RemoteKeyCode._(123, _omitEnumNames ? '' : 'KEYCODE_MOVE_END');

  /// Insert key.
  /// Toggles insert / overwrite edit mode.
  static const RemoteKeyCode KEYCODE_INSERT =
      RemoteKeyCode._(124, _omitEnumNames ? '' : 'KEYCODE_INSERT');

  /// Forward key.
  /// Navigates forward in the history stack.  Complement of KEYCODE_BACK.
  static const RemoteKeyCode KEYCODE_FORWARD =
      RemoteKeyCode._(125, _omitEnumNames ? '' : 'KEYCODE_FORWARD');

  /// Play media key.
  static const RemoteKeyCode KEYCODE_MEDIA_PLAY =
      RemoteKeyCode._(126, _omitEnumNames ? '' : 'KEYCODE_MEDIA_PLAY');

  /// Pause media key.
  static const RemoteKeyCode KEYCODE_MEDIA_PAUSE =
      RemoteKeyCode._(127, _omitEnumNames ? '' : 'KEYCODE_MEDIA_PAUSE');

  /// Close media key.
  /// May be used to close a CD tray, for example.
  static const RemoteKeyCode KEYCODE_MEDIA_CLOSE =
      RemoteKeyCode._(128, _omitEnumNames ? '' : 'KEYCODE_MEDIA_CLOSE');

  /// Eject media key.
  /// May be used to eject a CD tray, for example.
  static const RemoteKeyCode KEYCODE_MEDIA_EJECT =
      RemoteKeyCode._(129, _omitEnumNames ? '' : 'KEYCODE_MEDIA_EJECT');

  /// Record media key.
  static const RemoteKeyCode KEYCODE_MEDIA_RECORD =
      RemoteKeyCode._(130, _omitEnumNames ? '' : 'KEYCODE_MEDIA_RECORD');

  /// F1 key.
  static const RemoteKeyCode KEYCODE_F1 =
      RemoteKeyCode._(131, _omitEnumNames ? '' : 'KEYCODE_F1');

  /// F2 key.
  static const RemoteKeyCode KEYCODE_F2 =
      RemoteKeyCode._(132, _omitEnumNames ? '' : 'KEYCODE_F2');

  /// F3 key.
  static const RemoteKeyCode KEYCODE_F3 =
      RemoteKeyCode._(133, _omitEnumNames ? '' : 'KEYCODE_F3');

  /// F4 key.
  static const RemoteKeyCode KEYCODE_F4 =
      RemoteKeyCode._(134, _omitEnumNames ? '' : 'KEYCODE_F4');

  /// F5 key.
  static const RemoteKeyCode KEYCODE_F5 =
      RemoteKeyCode._(135, _omitEnumNames ? '' : 'KEYCODE_F5');

  /// F6 key.
  static const RemoteKeyCode KEYCODE_F6 =
      RemoteKeyCode._(136, _omitEnumNames ? '' : 'KEYCODE_F6');

  /// F7 key.
  static const RemoteKeyCode KEYCODE_F7 =
      RemoteKeyCode._(137, _omitEnumNames ? '' : 'KEYCODE_F7');

  /// F8 key.
  static const RemoteKeyCode KEYCODE_F8 =
      RemoteKeyCode._(138, _omitEnumNames ? '' : 'KEYCODE_F8');

  /// F9 key.
  static const RemoteKeyCode KEYCODE_F9 =
      RemoteKeyCode._(139, _omitEnumNames ? '' : 'KEYCODE_F9');

  /// F10 key.
  static const RemoteKeyCode KEYCODE_F10 =
      RemoteKeyCode._(140, _omitEnumNames ? '' : 'KEYCODE_F10');

  /// F11 key.
  static const RemoteKeyCode KEYCODE_F11 =
      RemoteKeyCode._(141, _omitEnumNames ? '' : 'KEYCODE_F11');

  /// F12 key.
  static const RemoteKeyCode KEYCODE_F12 =
      RemoteKeyCode._(142, _omitEnumNames ? '' : 'KEYCODE_F12');

  /// Num Lock key.
  /// This is the Num Lock key; it is different from KEYCODE_NUM.
  /// This key alters the behavior of other keys on the numeric keypad.
  static const RemoteKeyCode KEYCODE_NUM_LOCK =
      RemoteKeyCode._(143, _omitEnumNames ? '' : 'KEYCODE_NUM_LOCK');

  /// Numeric keypad '0' key.
  static const RemoteKeyCode KEYCODE_NUMPAD_0 =
      RemoteKeyCode._(144, _omitEnumNames ? '' : 'KEYCODE_NUMPAD_0');

  /// Numeric keypad '1' key.
  static const RemoteKeyCode KEYCODE_NUMPAD_1 =
      RemoteKeyCode._(145, _omitEnumNames ? '' : 'KEYCODE_NUMPAD_1');

  /// Numeric keypad '2' key.
  static const RemoteKeyCode KEYCODE_NUMPAD_2 =
      RemoteKeyCode._(146, _omitEnumNames ? '' : 'KEYCODE_NUMPAD_2');

  /// Numeric keypad '3' key.
  static const RemoteKeyCode KEYCODE_NUMPAD_3 =
      RemoteKeyCode._(147, _omitEnumNames ? '' : 'KEYCODE_NUMPAD_3');

  /// Numeric keypad '4' key.
  static const RemoteKeyCode KEYCODE_NUMPAD_4 =
      RemoteKeyCode._(148, _omitEnumNames ? '' : 'KEYCODE_NUMPAD_4');

  /// Numeric keypad '5' key.
  static const RemoteKeyCode KEYCODE_NUMPAD_5 =
      RemoteKeyCode._(149, _omitEnumNames ? '' : 'KEYCODE_NUMPAD_5');

  /// Numeric keypad '6' key.
  static const RemoteKeyCode KEYCODE_NUMPAD_6 =
      RemoteKeyCode._(150, _omitEnumNames ? '' : 'KEYCODE_NUMPAD_6');

  /// Numeric keypad '7' key.
  static const RemoteKeyCode KEYCODE_NUMPAD_7 =
      RemoteKeyCode._(151, _omitEnumNames ? '' : 'KEYCODE_NUMPAD_7');

  /// Numeric keypad '8' key.
  static const RemoteKeyCode KEYCODE_NUMPAD_8 =
      RemoteKeyCode._(152, _omitEnumNames ? '' : 'KEYCODE_NUMPAD_8');

  /// Numeric keypad '9' key.
  static const RemoteKeyCode KEYCODE_NUMPAD_9 =
      RemoteKeyCode._(153, _omitEnumNames ? '' : 'KEYCODE_NUMPAD_9');

  /// Numeric keypad '/' key (for division).
  static const RemoteKeyCode KEYCODE_NUMPAD_DIVIDE =
      RemoteKeyCode._(154, _omitEnumNames ? '' : 'KEYCODE_NUMPAD_DIVIDE');

  /// Numeric keypad '*' key (for multiplication).
  static const RemoteKeyCode KEYCODE_NUMPAD_MULTIPLY =
      RemoteKeyCode._(155, _omitEnumNames ? '' : 'KEYCODE_NUMPAD_MULTIPLY');

  /// Numeric keypad '-' key (for subtraction).
  static const RemoteKeyCode KEYCODE_NUMPAD_SUBTRACT =
      RemoteKeyCode._(156, _omitEnumNames ? '' : 'KEYCODE_NUMPAD_SUBTRACT');

  /// Numeric keypad '+' key (for addition).
  static const RemoteKeyCode KEYCODE_NUMPAD_ADD =
      RemoteKeyCode._(157, _omitEnumNames ? '' : 'KEYCODE_NUMPAD_ADD');

  /// Numeric keypad '.' key (for decimals or digit grouping).
  static const RemoteKeyCode KEYCODE_NUMPAD_DOT =
      RemoteKeyCode._(158, _omitEnumNames ? '' : 'KEYCODE_NUMPAD_DOT');

  /// Numeric keypad ',' key (for decimals or digit grouping).
  static const RemoteKeyCode KEYCODE_NUMPAD_COMMA =
      RemoteKeyCode._(159, _omitEnumNames ? '' : 'KEYCODE_NUMPAD_COMMA');

  /// Numeric keypad Enter key.
  static const RemoteKeyCode KEYCODE_NUMPAD_ENTER =
      RemoteKeyCode._(160, _omitEnumNames ? '' : 'KEYCODE_NUMPAD_ENTER');

  /// Numeric keypad '=' key.
  static const RemoteKeyCode KEYCODE_NUMPAD_EQUALS =
      RemoteKeyCode._(161, _omitEnumNames ? '' : 'KEYCODE_NUMPAD_EQUALS');

  /// Numeric keypad '(' key.
  static const RemoteKeyCode KEYCODE_NUMPAD_LEFT_PAREN =
      RemoteKeyCode._(162, _omitEnumNames ? '' : 'KEYCODE_NUMPAD_LEFT_PAREN');

  /// Numeric keypad ')' key.
  static const RemoteKeyCode KEYCODE_NUMPAD_RIGHT_PAREN =
      RemoteKeyCode._(163, _omitEnumNames ? '' : 'KEYCODE_NUMPAD_RIGHT_PAREN');

  /// Volume Mute key.
  /// Mutes the speaker, unlike KEYCODE_MUTE.
  /// This key should normally be implemented as a toggle such that the first press
  /// mutes the speaker and the second press restores the original volume.
  static const RemoteKeyCode KEYCODE_VOLUME_MUTE =
      RemoteKeyCode._(164, _omitEnumNames ? '' : 'KEYCODE_VOLUME_MUTE');

  /// Info key.
  /// Common on TV remotes to show additional information related to what is
  /// currently being viewed.
  static const RemoteKeyCode KEYCODE_INFO =
      RemoteKeyCode._(165, _omitEnumNames ? '' : 'KEYCODE_INFO');

  /// Channel up key.
  /// On TV remotes, increments the television channel.
  static const RemoteKeyCode KEYCODE_CHANNEL_UP =
      RemoteKeyCode._(166, _omitEnumNames ? '' : 'KEYCODE_CHANNEL_UP');

  /// Channel down key.
  /// On TV remotes, decrements the television channel.
  static const RemoteKeyCode KEYCODE_CHANNEL_DOWN =
      RemoteKeyCode._(167, _omitEnumNames ? '' : 'KEYCODE_CHANNEL_DOWN');

  /// Zoom in key.
  static const RemoteKeyCode KEYCODE_ZOOM_IN =
      RemoteKeyCode._(168, _omitEnumNames ? '' : 'KEYCODE_ZOOM_IN');

  /// Zoom out key.
  static const RemoteKeyCode KEYCODE_ZOOM_OUT =
      RemoteKeyCode._(169, _omitEnumNames ? '' : 'KEYCODE_ZOOM_OUT');

  /// TV key.
  /// On TV remotes, switches to viewing live TV.
  static const RemoteKeyCode KEYCODE_TV =
      RemoteKeyCode._(170, _omitEnumNames ? '' : 'KEYCODE_TV');

  /// Window key.
  /// On TV remotes, toggles picture-in-picture mode or other windowing functions.
  static const RemoteKeyCode KEYCODE_WINDOW =
      RemoteKeyCode._(171, _omitEnumNames ? '' : 'KEYCODE_WINDOW');

  /// Guide key.
  /// On TV remotes, shows a programming guide.
  static const RemoteKeyCode KEYCODE_GUIDE =
      RemoteKeyCode._(172, _omitEnumNames ? '' : 'KEYCODE_GUIDE');

  /// DVR key.
  /// On some TV remotes, switches to a DVR mode for recorded shows.
  static const RemoteKeyCode KEYCODE_DVR =
      RemoteKeyCode._(173, _omitEnumNames ? '' : 'KEYCODE_DVR');

  /// Bookmark key.
  /// On some TV remotes, bookmarks content or web pages.
  static const RemoteKeyCode KEYCODE_BOOKMARK =
      RemoteKeyCode._(174, _omitEnumNames ? '' : 'KEYCODE_BOOKMARK');

  /// Toggle captions key.
  /// Switches the mode for closed-captioning text, for example during television shows.
  static const RemoteKeyCode KEYCODE_CAPTIONS =
      RemoteKeyCode._(175, _omitEnumNames ? '' : 'KEYCODE_CAPTIONS');

  /// Settings key.
  /// Starts the system settings activity.
  static const RemoteKeyCode KEYCODE_SETTINGS =
      RemoteKeyCode._(176, _omitEnumNames ? '' : 'KEYCODE_SETTINGS');

  /// TV power key.
  /// On TV remotes, toggles the power on a television screen.
  static const RemoteKeyCode KEYCODE_TV_POWER =
      RemoteKeyCode._(177, _omitEnumNames ? '' : 'KEYCODE_TV_POWER');

  /// TV input key.
  /// On TV remotes, switches the input on a television screen.
  static const RemoteKeyCode KEYCODE_TV_INPUT =
      RemoteKeyCode._(178, _omitEnumNames ? '' : 'KEYCODE_TV_INPUT');

  /// Set-top-box power key.
  /// On TV remotes, toggles the power on an external Set-top-box.
  static const RemoteKeyCode KEYCODE_STB_POWER =
      RemoteKeyCode._(179, _omitEnumNames ? '' : 'KEYCODE_STB_POWER');

  /// Set-top-box input key.
  /// On TV remotes, switches the input mode on an external Set-top-box.
  static const RemoteKeyCode KEYCODE_STB_INPUT =
      RemoteKeyCode._(180, _omitEnumNames ? '' : 'KEYCODE_STB_INPUT');

  /// A/V Receiver power key.
  /// On TV remotes, toggles the power on an external A/V Receiver.
  static const RemoteKeyCode KEYCODE_AVR_POWER =
      RemoteKeyCode._(181, _omitEnumNames ? '' : 'KEYCODE_AVR_POWER');

  /// A/V Receiver input key.
  /// On TV remotes, switches the input mode on an external A/V Receiver.
  static const RemoteKeyCode KEYCODE_AVR_INPUT =
      RemoteKeyCode._(182, _omitEnumNames ? '' : 'KEYCODE_AVR_INPUT');

  /// Red "programmable" key.
  /// On TV remotes, acts as a contextual/programmable key.
  static const RemoteKeyCode KEYCODE_PROG_RED =
      RemoteKeyCode._(183, _omitEnumNames ? '' : 'KEYCODE_PROG_RED');

  /// Green "programmable" key.
  /// On TV remotes, actsas a contextual/programmable key.
  static const RemoteKeyCode KEYCODE_PROG_GREEN =
      RemoteKeyCode._(184, _omitEnumNames ? '' : 'KEYCODE_PROG_GREEN');

  /// Yellow "programmable" key.
  /// On TV remotes, acts as a contextual/programmable key.
  static const RemoteKeyCode KEYCODE_PROG_YELLOW =
      RemoteKeyCode._(185, _omitEnumNames ? '' : 'KEYCODE_PROG_YELLOW');

  /// Blue "programmable" key.
  /// On TV remotes, acts as a contextual/programmable key.
  static const RemoteKeyCode KEYCODE_PROG_BLUE =
      RemoteKeyCode._(186, _omitEnumNames ? '' : 'KEYCODE_PROG_BLUE');

  /// App switch key.
  /// Should bring up the application switcher dialog.
  static const RemoteKeyCode KEYCODE_APP_SWITCH =
      RemoteKeyCode._(187, _omitEnumNames ? '' : 'KEYCODE_APP_SWITCH');

  /// Generic Game Pad Button #1.*/
  static const RemoteKeyCode KEYCODE_BUTTON_1 =
      RemoteKeyCode._(188, _omitEnumNames ? '' : 'KEYCODE_BUTTON_1');

  /// Generic Game Pad Button #2.*/
  static const RemoteKeyCode KEYCODE_BUTTON_2 =
      RemoteKeyCode._(189, _omitEnumNames ? '' : 'KEYCODE_BUTTON_2');

  /// Generic Game Pad Button #3.*/
  static const RemoteKeyCode KEYCODE_BUTTON_3 =
      RemoteKeyCode._(190, _omitEnumNames ? '' : 'KEYCODE_BUTTON_3');

  /// Generic Game Pad Button #4.*/
  static const RemoteKeyCode KEYCODE_BUTTON_4 =
      RemoteKeyCode._(191, _omitEnumNames ? '' : 'KEYCODE_BUTTON_4');

  /// Generic Game Pad Button #5.*/
  static const RemoteKeyCode KEYCODE_BUTTON_5 =
      RemoteKeyCode._(192, _omitEnumNames ? '' : 'KEYCODE_BUTTON_5');

  /// Generic Game Pad Button #6.*/
  static const RemoteKeyCode KEYCODE_BUTTON_6 =
      RemoteKeyCode._(193, _omitEnumNames ? '' : 'KEYCODE_BUTTON_6');

  /// Generic Game Pad Button #7.*/
  static const RemoteKeyCode KEYCODE_BUTTON_7 =
      RemoteKeyCode._(194, _omitEnumNames ? '' : 'KEYCODE_BUTTON_7');

  /// Generic Game Pad Button #8.*/
  static const RemoteKeyCode KEYCODE_BUTTON_8 =
      RemoteKeyCode._(195, _omitEnumNames ? '' : 'KEYCODE_BUTTON_8');

  /// Generic Game Pad Button #9.*/
  static const RemoteKeyCode KEYCODE_BUTTON_9 =
      RemoteKeyCode._(196, _omitEnumNames ? '' : 'KEYCODE_BUTTON_9');

  /// Generic Game Pad Button #10.*/
  static const RemoteKeyCode KEYCODE_BUTTON_10 =
      RemoteKeyCode._(197, _omitEnumNames ? '' : 'KEYCODE_BUTTON_10');

  /// Generic Game Pad Button #11.*/
  static const RemoteKeyCode KEYCODE_BUTTON_11 =
      RemoteKeyCode._(198, _omitEnumNames ? '' : 'KEYCODE_BUTTON_11');

  /// Generic Game Pad Button #12.*/
  static const RemoteKeyCode KEYCODE_BUTTON_12 =
      RemoteKeyCode._(199, _omitEnumNames ? '' : 'KEYCODE_BUTTON_12');

  /// Generic Game Pad Button #13.*/
  static const RemoteKeyCode KEYCODE_BUTTON_13 =
      RemoteKeyCode._(200, _omitEnumNames ? '' : 'KEYCODE_BUTTON_13');

  /// Generic Game Pad Button #14.*/
  static const RemoteKeyCode KEYCODE_BUTTON_14 =
      RemoteKeyCode._(201, _omitEnumNames ? '' : 'KEYCODE_BUTTON_14');

  /// Generic Game Pad Button #15.*/
  static const RemoteKeyCode KEYCODE_BUTTON_15 =
      RemoteKeyCode._(202, _omitEnumNames ? '' : 'KEYCODE_BUTTON_15');

  /// Generic Game Pad Button #16.*/
  static const RemoteKeyCode KEYCODE_BUTTON_16 =
      RemoteKeyCode._(203, _omitEnumNames ? '' : 'KEYCODE_BUTTON_16');

  /// Language Switch key.
  /// Toggles the current input language such as switching between English and Japanese on
  /// a QWERTY keyboard.  On some devices, the same function may be performed by
  /// pressing Shift+Spacebar.
  static const RemoteKeyCode KEYCODE_LANGUAGE_SWITCH =
      RemoteKeyCode._(204, _omitEnumNames ? '' : 'KEYCODE_LANGUAGE_SWITCH');

  /// Manner Mode key.
  /// Toggles silent or vibrate mode on and off to make the device behave more politely
  /// in certain settings such as on a crowded train.  On some devices, the key may only
  /// operate when long-pressed.
  static const RemoteKeyCode KEYCODE_MANNER_MODE =
      RemoteKeyCode._(205, _omitEnumNames ? '' : 'KEYCODE_MANNER_MODE');

  /// 3D Mode key.
  /// Toggles the display between 2D and 3D mode.
  static const RemoteKeyCode KEYCODE_3D_MODE =
      RemoteKeyCode._(206, _omitEnumNames ? '' : 'KEYCODE_3D_MODE');

  /// Contacts special function key.
  /// Used to launch an address book application.
  static const RemoteKeyCode KEYCODE_CONTACTS =
      RemoteKeyCode._(207, _omitEnumNames ? '' : 'KEYCODE_CONTACTS');

  /// Calendar special function key.
  /// Used to launch a calendar application.
  static const RemoteKeyCode KEYCODE_CALENDAR =
      RemoteKeyCode._(208, _omitEnumNames ? '' : 'KEYCODE_CALENDAR');

  /// Music special function key.
  /// Used to launch a music player application.
  static const RemoteKeyCode KEYCODE_MUSIC =
      RemoteKeyCode._(209, _omitEnumNames ? '' : 'KEYCODE_MUSIC');

  /// Calculator special function key.
  /// Used to launch a calculator application.
  static const RemoteKeyCode KEYCODE_CALCULATOR =
      RemoteKeyCode._(210, _omitEnumNames ? '' : 'KEYCODE_CALCULATOR');

  /// Japanese full-width / half-width key.
  static const RemoteKeyCode KEYCODE_ZENKAKU_HANKAKU =
      RemoteKeyCode._(211, _omitEnumNames ? '' : 'KEYCODE_ZENKAKU_HANKAKU');

  /// Japanese alphanumeric key.
  static const RemoteKeyCode KEYCODE_EISU =
      RemoteKeyCode._(212, _omitEnumNames ? '' : 'KEYCODE_EISU');

  /// Japanese non-conversion key.
  static const RemoteKeyCode KEYCODE_MUHENKAN =
      RemoteKeyCode._(213, _omitEnumNames ? '' : 'KEYCODE_MUHENKAN');

  /// Japanese conversion key.
  static const RemoteKeyCode KEYCODE_HENKAN =
      RemoteKeyCode._(214, _omitEnumNames ? '' : 'KEYCODE_HENKAN');

  /// Japanese katakana / hiragana key.
  static const RemoteKeyCode KEYCODE_KATAKANA_HIRAGANA =
      RemoteKeyCode._(215, _omitEnumNames ? '' : 'KEYCODE_KATAKANA_HIRAGANA');

  /// Japanese Yen key.
  static const RemoteKeyCode KEYCODE_YEN =
      RemoteKeyCode._(216, _omitEnumNames ? '' : 'KEYCODE_YEN');

  /// Japanese Ro key.
  static const RemoteKeyCode KEYCODE_RO =
      RemoteKeyCode._(217, _omitEnumNames ? '' : 'KEYCODE_RO');

  /// Japanese kana key.
  static const RemoteKeyCode KEYCODE_KANA =
      RemoteKeyCode._(218, _omitEnumNames ? '' : 'KEYCODE_KANA');

  /// Assist key.
  /// Launches the global assist activity.  Not delivered to applications.
  static const RemoteKeyCode KEYCODE_ASSIST =
      RemoteKeyCode._(219, _omitEnumNames ? '' : 'KEYCODE_ASSIST');

  /// Brightness Down key.
  /// Adjusts the screen brightness down.
  static const RemoteKeyCode KEYCODE_BRIGHTNESS_DOWN =
      RemoteKeyCode._(220, _omitEnumNames ? '' : 'KEYCODE_BRIGHTNESS_DOWN');

  /// Brightness Up key.
  /// Adjusts the screen brightness up.
  static const RemoteKeyCode KEYCODE_BRIGHTNESS_UP =
      RemoteKeyCode._(221, _omitEnumNames ? '' : 'KEYCODE_BRIGHTNESS_UP');

  /// Audio Track key.
  /// Switches the audio tracks.
  static const RemoteKeyCode KEYCODE_MEDIA_AUDIO_TRACK =
      RemoteKeyCode._(222, _omitEnumNames ? '' : 'KEYCODE_MEDIA_AUDIO_TRACK');

  /// Sleep key.
  /// Puts the device to sleep.  Behaves somewhat like KEYCODE_POWER but it
  /// has no effect if the device is already asleep.
  static const RemoteKeyCode KEYCODE_SLEEP =
      RemoteKeyCode._(223, _omitEnumNames ? '' : 'KEYCODE_SLEEP');

  /// Wakeup key.
  /// Wakes up the device.  Behaves somewhat like KEYCODE_POWER but it
  /// has no effect if the device is already awake.
  static const RemoteKeyCode KEYCODE_WAKEUP =
      RemoteKeyCode._(224, _omitEnumNames ? '' : 'KEYCODE_WAKEUP');

  /// Pairing key.
  /// Initiates peripheral pairing mode. Useful for pairing remote control
  /// devices or game controllers, especially if no other input mode is
  /// available.
  static const RemoteKeyCode KEYCODE_PAIRING =
      RemoteKeyCode._(225, _omitEnumNames ? '' : 'KEYCODE_PAIRING');

  /// Media Top Menu key.
  /// Goes to the top of media menu.
  static const RemoteKeyCode KEYCODE_MEDIA_TOP_MENU =
      RemoteKeyCode._(226, _omitEnumNames ? '' : 'KEYCODE_MEDIA_TOP_MENU');

  /// '11' key.
  static const RemoteKeyCode KEYCODE_11 =
      RemoteKeyCode._(227, _omitEnumNames ? '' : 'KEYCODE_11');

  /// '12' key.
  static const RemoteKeyCode KEYCODE_12 =
      RemoteKeyCode._(228, _omitEnumNames ? '' : 'KEYCODE_12');

  /// Last Channel key.
  /// Goes to the last viewed channel.
  static const RemoteKeyCode KEYCODE_LAST_CHANNEL =
      RemoteKeyCode._(229, _omitEnumNames ? '' : 'KEYCODE_LAST_CHANNEL');

  /// TV data service key.
  /// Displays data services like weather, sports.
  static const RemoteKeyCode KEYCODE_TV_DATA_SERVICE =
      RemoteKeyCode._(230, _omitEnumNames ? '' : 'KEYCODE_TV_DATA_SERVICE');

  /// Voice Assist key.
  /// Launches the global voice assist activity. Not delivered to applications.
  static const RemoteKeyCode KEYCODE_VOICE_ASSIST =
      RemoteKeyCode._(231, _omitEnumNames ? '' : 'KEYCODE_VOICE_ASSIST');

  /// Radio key.
  /// Toggles TV service / Radio service.
  static const RemoteKeyCode KEYCODE_TV_RADIO_SERVICE =
      RemoteKeyCode._(232, _omitEnumNames ? '' : 'KEYCODE_TV_RADIO_SERVICE');

  /// Teletext key.
  /// Displays Teletext service.
  static const RemoteKeyCode KEYCODE_TV_TELETEXT =
      RemoteKeyCode._(233, _omitEnumNames ? '' : 'KEYCODE_TV_TELETEXT');

  /// Number entry key.
  /// Initiates to enter multi-digit channel nubmber when each digit key is assigned
  /// for selecting separate channel. Corresponds to Number Entry Mode (0x1D) of CEC
  /// User Control Code.
  static const RemoteKeyCode KEYCODE_TV_NUMBER_ENTRY =
      RemoteKeyCode._(234, _omitEnumNames ? '' : 'KEYCODE_TV_NUMBER_ENTRY');

  /// Analog Terrestrial key.
  /// Switches to analog terrestrial broadcast service.
  static const RemoteKeyCode KEYCODE_TV_TERRESTRIAL_ANALOG = RemoteKeyCode._(
      235, _omitEnumNames ? '' : 'KEYCODE_TV_TERRESTRIAL_ANALOG');

  /// Digital Terrestrial key.
  /// Switches to digital terrestrial broadcast service.
  static const RemoteKeyCode KEYCODE_TV_TERRESTRIAL_DIGITAL = RemoteKeyCode._(
      236, _omitEnumNames ? '' : 'KEYCODE_TV_TERRESTRIAL_DIGITAL');

  /// Satellite key.
  /// Switches to digital satellite broadcast service.
  static const RemoteKeyCode KEYCODE_TV_SATELLITE =
      RemoteKeyCode._(237, _omitEnumNames ? '' : 'KEYCODE_TV_SATELLITE');

  /// BS key.
  /// Switches to BS digital satellite broadcasting service available in Japan.
  static const RemoteKeyCode KEYCODE_TV_SATELLITE_BS =
      RemoteKeyCode._(238, _omitEnumNames ? '' : 'KEYCODE_TV_SATELLITE_BS');

  /// CS key.
  /// Switches to CS digital satellite broadcasting service available in Japan.
  static const RemoteKeyCode KEYCODE_TV_SATELLITE_CS =
      RemoteKeyCode._(239, _omitEnumNames ? '' : 'KEYCODE_TV_SATELLITE_CS');

  /// BS/CS key.
  /// Toggles between BS and CS digital satellite services.
  static const RemoteKeyCode KEYCODE_TV_SATELLITE_SERVICE = RemoteKeyCode._(
      240, _omitEnumNames ? '' : 'KEYCODE_TV_SATELLITE_SERVICE');

  /// Toggle Network key.
  /// Toggles selecting broadcast services.
  static const RemoteKeyCode KEYCODE_TV_NETWORK =
      RemoteKeyCode._(241, _omitEnumNames ? '' : 'KEYCODE_TV_NETWORK');

  /// Antenna/Cable key.
  /// Toggles broadcast input source between antenna and cable.
  static const RemoteKeyCode KEYCODE_TV_ANTENNA_CABLE =
      RemoteKeyCode._(242, _omitEnumNames ? '' : 'KEYCODE_TV_ANTENNA_CABLE');

  /// HDMI #1 key.
  /// Switches to HDMI input #1.
  static const RemoteKeyCode KEYCODE_TV_INPUT_HDMI_1 =
      RemoteKeyCode._(243, _omitEnumNames ? '' : 'KEYCODE_TV_INPUT_HDMI_1');

  /// HDMI #2 key.
  /// Switches to HDMI input #2.
  static const RemoteKeyCode KEYCODE_TV_INPUT_HDMI_2 =
      RemoteKeyCode._(244, _omitEnumNames ? '' : 'KEYCODE_TV_INPUT_HDMI_2');

  /// HDMI #3 key.
  /// Switches to HDMI input #3.
  static const RemoteKeyCode KEYCODE_TV_INPUT_HDMI_3 =
      RemoteKeyCode._(245, _omitEnumNames ? '' : 'KEYCODE_TV_INPUT_HDMI_3');

  /// HDMI #4 key.
  /// Switches to HDMI input #4.
  static const RemoteKeyCode KEYCODE_TV_INPUT_HDMI_4 =
      RemoteKeyCode._(246, _omitEnumNames ? '' : 'KEYCODE_TV_INPUT_HDMI_4');

  /// Composite #1 key.
  /// Switches to composite video input #1.
  static const RemoteKeyCode KEYCODE_TV_INPUT_COMPOSITE_1 = RemoteKeyCode._(
      247, _omitEnumNames ? '' : 'KEYCODE_TV_INPUT_COMPOSITE_1');

  /// Composite #2 key.
  /// Switches to composite video input #2.
  static const RemoteKeyCode KEYCODE_TV_INPUT_COMPOSITE_2 = RemoteKeyCode._(
      248, _omitEnumNames ? '' : 'KEYCODE_TV_INPUT_COMPOSITE_2');

  /// Component #1 key.
  /// Switches to component video input #1.
  static const RemoteKeyCode KEYCODE_TV_INPUT_COMPONENT_1 = RemoteKeyCode._(
      249, _omitEnumNames ? '' : 'KEYCODE_TV_INPUT_COMPONENT_1');

  /// Component #2 key.
  /// Switches to component video input #2.
  static const RemoteKeyCode KEYCODE_TV_INPUT_COMPONENT_2 = RemoteKeyCode._(
      250, _omitEnumNames ? '' : 'KEYCODE_TV_INPUT_COMPONENT_2');

  /// VGA #1 key.
  /// Switches to VGA (analog RGB) input #1.
  static const RemoteKeyCode KEYCODE_TV_INPUT_VGA_1 =
      RemoteKeyCode._(251, _omitEnumNames ? '' : 'KEYCODE_TV_INPUT_VGA_1');

  /// Audio description key.
  /// Toggles audio description off / on.
  static const RemoteKeyCode KEYCODE_TV_AUDIO_DESCRIPTION = RemoteKeyCode._(
      252, _omitEnumNames ? '' : 'KEYCODE_TV_AUDIO_DESCRIPTION');

  /// Audio description mixing volume up key.
  /// Louden audio description volume as compared with normal audio volume.
  static const RemoteKeyCode KEYCODE_TV_AUDIO_DESCRIPTION_MIX_UP =
      RemoteKeyCode._(
          253, _omitEnumNames ? '' : 'KEYCODE_TV_AUDIO_DESCRIPTION_MIX_UP');

  /// Audio description mixing volume down key.
  /// Lessen audio description volume as compared with normal audio volume.
  static const RemoteKeyCode KEYCODE_TV_AUDIO_DESCRIPTION_MIX_DOWN =
      RemoteKeyCode._(
          254, _omitEnumNames ? '' : 'KEYCODE_TV_AUDIO_DESCRIPTION_MIX_DOWN');

  /// Zoom mode key.
  /// Changes Zoom mode (Normal, Full, Zoom, Wide-zoom, etc.)
  static const RemoteKeyCode KEYCODE_TV_ZOOM_MODE =
      RemoteKeyCode._(255, _omitEnumNames ? '' : 'KEYCODE_TV_ZOOM_MODE');

  /// Contents menu key.
  /// Goes to the title list. Corresponds to Contents Menu (0x0B) of CEC User Control
  /// Code
  static const RemoteKeyCode KEYCODE_TV_CONTENTS_MENU =
      RemoteKeyCode._(256, _omitEnumNames ? '' : 'KEYCODE_TV_CONTENTS_MENU');

  /// Media context menu key.
  /// Goes to the context menu of media contents. Corresponds to Media Context-sensitive
  /// Menu (0x11) of CEC User Control Code.
  static const RemoteKeyCode KEYCODE_TV_MEDIA_CONTEXT_MENU = RemoteKeyCode._(
      257, _omitEnumNames ? '' : 'KEYCODE_TV_MEDIA_CONTEXT_MENU');

  /// Timer programming key.
  /// Goes to the timer recording menu. Corresponds to Timer Programming (0x54) of
  /// CEC User Control Code.
  static const RemoteKeyCode KEYCODE_TV_TIMER_PROGRAMMING = RemoteKeyCode._(
      258, _omitEnumNames ? '' : 'KEYCODE_TV_TIMER_PROGRAMMING');

  /// Help key.
  static const RemoteKeyCode KEYCODE_HELP =
      RemoteKeyCode._(259, _omitEnumNames ? '' : 'KEYCODE_HELP');
  static const RemoteKeyCode KEYCODE_NAVIGATE_PREVIOUS =
      RemoteKeyCode._(260, _omitEnumNames ? '' : 'KEYCODE_NAVIGATE_PREVIOUS');
  static const RemoteKeyCode KEYCODE_NAVIGATE_NEXT =
      RemoteKeyCode._(261, _omitEnumNames ? '' : 'KEYCODE_NAVIGATE_NEXT');
  static const RemoteKeyCode KEYCODE_NAVIGATE_IN =
      RemoteKeyCode._(262, _omitEnumNames ? '' : 'KEYCODE_NAVIGATE_IN');
  static const RemoteKeyCode KEYCODE_NAVIGATE_OUT =
      RemoteKeyCode._(263, _omitEnumNames ? '' : 'KEYCODE_NAVIGATE_OUT');

  /// Primary stem key for Wear
  /// Main power/reset button on watch.
  static const RemoteKeyCode KEYCODE_STEM_PRIMARY =
      RemoteKeyCode._(264, _omitEnumNames ? '' : 'KEYCODE_STEM_PRIMARY');

  /// Generic stem key 1 for Wear
  static const RemoteKeyCode KEYCODE_STEM_1 =
      RemoteKeyCode._(265, _omitEnumNames ? '' : 'KEYCODE_STEM_1');

  /// Generic stem key 2 for Wear
  static const RemoteKeyCode KEYCODE_STEM_2 =
      RemoteKeyCode._(266, _omitEnumNames ? '' : 'KEYCODE_STEM_2');

  /// Generic stem key 3 for Wear
  static const RemoteKeyCode KEYCODE_STEM_3 =
      RemoteKeyCode._(267, _omitEnumNames ? '' : 'KEYCODE_STEM_3');

  /// Directional Pad Up-Left
  static const RemoteKeyCode KEYCODE_DPAD_UP_LEFT =
      RemoteKeyCode._(268, _omitEnumNames ? '' : 'KEYCODE_DPAD_UP_LEFT');

  /// Directional Pad Down-Left
  static const RemoteKeyCode KEYCODE_DPAD_DOWN_LEFT =
      RemoteKeyCode._(269, _omitEnumNames ? '' : 'KEYCODE_DPAD_DOWN_LEFT');

  /// Directional Pad Up-Right
  static const RemoteKeyCode KEYCODE_DPAD_UP_RIGHT =
      RemoteKeyCode._(270, _omitEnumNames ? '' : 'KEYCODE_DPAD_UP_RIGHT');

  /// Directional Pad Down-Right
  static const RemoteKeyCode KEYCODE_DPAD_DOWN_RIGHT =
      RemoteKeyCode._(271, _omitEnumNames ? '' : 'KEYCODE_DPAD_DOWN_RIGHT');

  /// Skip forward media key
  static const RemoteKeyCode KEYCODE_MEDIA_SKIP_FORWARD =
      RemoteKeyCode._(272, _omitEnumNames ? '' : 'KEYCODE_MEDIA_SKIP_FORWARD');

  /// Skip backward media key
  static const RemoteKeyCode KEYCODE_MEDIA_SKIP_BACKWARD =
      RemoteKeyCode._(273, _omitEnumNames ? '' : 'KEYCODE_MEDIA_SKIP_BACKWARD');

  /// Step forward media key.
  /// Steps media forward one from at a time.
  static const RemoteKeyCode KEYCODE_MEDIA_STEP_FORWARD =
      RemoteKeyCode._(274, _omitEnumNames ? '' : 'KEYCODE_MEDIA_STEP_FORWARD');

  /// Step backward media key.
  /// Steps media backward one from at a time.
  static const RemoteKeyCode KEYCODE_MEDIA_STEP_BACKWARD =
      RemoteKeyCode._(275, _omitEnumNames ? '' : 'KEYCODE_MEDIA_STEP_BACKWARD');

  /// Put device to sleep unless a wakelock is held.
  static const RemoteKeyCode KEYCODE_SOFT_SLEEP =
      RemoteKeyCode._(276, _omitEnumNames ? '' : 'KEYCODE_SOFT_SLEEP');

  /// Cut key.
  static const RemoteKeyCode KEYCODE_CUT =
      RemoteKeyCode._(277, _omitEnumNames ? '' : 'KEYCODE_CUT');

  /// Copy key.
  static const RemoteKeyCode KEYCODE_COPY =
      RemoteKeyCode._(278, _omitEnumNames ? '' : 'KEYCODE_COPY');

  /// Paste key.
  static const RemoteKeyCode KEYCODE_PASTE =
      RemoteKeyCode._(279, _omitEnumNames ? '' : 'KEYCODE_PASTE');

  /// fingerprint navigation key, up.
  static const RemoteKeyCode KEYCODE_SYSTEM_NAVIGATION_UP = RemoteKeyCode._(
      280, _omitEnumNames ? '' : 'KEYCODE_SYSTEM_NAVIGATION_UP');

  /// fingerprint navigation key, down.
  static const RemoteKeyCode KEYCODE_SYSTEM_NAVIGATION_DOWN = RemoteKeyCode._(
      281, _omitEnumNames ? '' : 'KEYCODE_SYSTEM_NAVIGATION_DOWN');

  /// fingerprint navigation key, left.
  static const RemoteKeyCode KEYCODE_SYSTEM_NAVIGATION_LEFT = RemoteKeyCode._(
      282, _omitEnumNames ? '' : 'KEYCODE_SYSTEM_NAVIGATION_LEFT');

  /// fingerprint navigation key, right.
  static const RemoteKeyCode KEYCODE_SYSTEM_NAVIGATION_RIGHT = RemoteKeyCode._(
      283, _omitEnumNames ? '' : 'KEYCODE_SYSTEM_NAVIGATION_RIGHT');

  /// all apps
  static const RemoteKeyCode KEYCODE_ALL_APPS =
      RemoteKeyCode._(284, _omitEnumNames ? '' : 'KEYCODE_ALL_APPS');

  /// refresh key
  static const RemoteKeyCode KEYCODE_REFRESH =
      RemoteKeyCode._(285, _omitEnumNames ? '' : 'KEYCODE_REFRESH');

  /// Thumbs up key. Apps can use this to let user upvote content.
  static const RemoteKeyCode KEYCODE_THUMBS_UP =
      RemoteKeyCode._(286, _omitEnumNames ? '' : 'KEYCODE_THUMBS_UP');

  /// Thumbs down key. Apps can use this to let user downvote content.
  static const RemoteKeyCode KEYCODE_THUMBS_DOWN =
      RemoteKeyCode._(287, _omitEnumNames ? '' : 'KEYCODE_THUMBS_DOWN');

  /// Used to switch current account that is consuming content.
  /// May be consumed by system to switch current viewer profile.
  static const RemoteKeyCode KEYCODE_PROFILE_SWITCH =
      RemoteKeyCode._(288, _omitEnumNames ? '' : 'KEYCODE_PROFILE_SWITCH');
  static const RemoteKeyCode KEYCODE_VIDEO_APP_1 =
      RemoteKeyCode._(289, _omitEnumNames ? '' : 'KEYCODE_VIDEO_APP_1');
  static const RemoteKeyCode KEYCODE_VIDEO_APP_2 =
      RemoteKeyCode._(290, _omitEnumNames ? '' : 'KEYCODE_VIDEO_APP_2');
  static const RemoteKeyCode KEYCODE_VIDEO_APP_3 =
      RemoteKeyCode._(291, _omitEnumNames ? '' : 'KEYCODE_VIDEO_APP_3');
  static const RemoteKeyCode KEYCODE_VIDEO_APP_4 =
      RemoteKeyCode._(292, _omitEnumNames ? '' : 'KEYCODE_VIDEO_APP_4');
  static const RemoteKeyCode KEYCODE_VIDEO_APP_5 =
      RemoteKeyCode._(293, _omitEnumNames ? '' : 'KEYCODE_VIDEO_APP_5');
  static const RemoteKeyCode KEYCODE_VIDEO_APP_6 =
      RemoteKeyCode._(294, _omitEnumNames ? '' : 'KEYCODE_VIDEO_APP_6');
  static const RemoteKeyCode KEYCODE_VIDEO_APP_7 =
      RemoteKeyCode._(295, _omitEnumNames ? '' : 'KEYCODE_VIDEO_APP_7');
  static const RemoteKeyCode KEYCODE_VIDEO_APP_8 =
      RemoteKeyCode._(296, _omitEnumNames ? '' : 'KEYCODE_VIDEO_APP_8');
  static const RemoteKeyCode KEYCODE_FEATURED_APP_1 =
      RemoteKeyCode._(297, _omitEnumNames ? '' : 'KEYCODE_FEATURED_APP_1');
  static const RemoteKeyCode KEYCODE_FEATURED_APP_2 =
      RemoteKeyCode._(298, _omitEnumNames ? '' : 'KEYCODE_FEATURED_APP_2');
  static const RemoteKeyCode KEYCODE_FEATURED_APP_3 =
      RemoteKeyCode._(299, _omitEnumNames ? '' : 'KEYCODE_FEATURED_APP_3');
  static const RemoteKeyCode KEYCODE_FEATURED_APP_4 =
      RemoteKeyCode._(300, _omitEnumNames ? '' : 'KEYCODE_FEATURED_APP_4');
  static const RemoteKeyCode KEYCODE_DEMO_APP_1 =
      RemoteKeyCode._(301, _omitEnumNames ? '' : 'KEYCODE_DEMO_APP_1');
  static const RemoteKeyCode KEYCODE_DEMO_APP_2 =
      RemoteKeyCode._(302, _omitEnumNames ? '' : 'KEYCODE_DEMO_APP_2');
  static const RemoteKeyCode KEYCODE_DEMO_APP_3 =
      RemoteKeyCode._(303, _omitEnumNames ? '' : 'KEYCODE_DEMO_APP_3');
  static const RemoteKeyCode KEYCODE_DEMO_APP_4 =
      RemoteKeyCode._(304, _omitEnumNames ? '' : 'KEYCODE_DEMO_APP_4');

  static const $core.List<RemoteKeyCode> values = <RemoteKeyCode>[
    KEYCODE_UNKNOWN,
    KEYCODE_SOFT_LEFT,
    KEYCODE_SOFT_RIGHT,
    KEYCODE_HOME,
    KEYCODE_BACK,
    KEYCODE_CALL,
    KEYCODE_ENDCALL,
    KEYCODE_0,
    KEYCODE_1,
    KEYCODE_2,
    KEYCODE_3,
    KEYCODE_4,
    KEYCODE_5,
    KEYCODE_6,
    KEYCODE_7,
    KEYCODE_8,
    KEYCODE_9,
    KEYCODE_STAR,
    KEYCODE_POUND,
    KEYCODE_DPAD_UP,
    KEYCODE_DPAD_DOWN,
    KEYCODE_DPAD_LEFT,
    KEYCODE_DPAD_RIGHT,
    KEYCODE_DPAD_CENTER,
    KEYCODE_VOLUME_UP,
    KEYCODE_VOLUME_DOWN,
    KEYCODE_POWER,
    KEYCODE_CAMERA,
    KEYCODE_CLEAR,
    KEYCODE_A,
    KEYCODE_B,
    KEYCODE_C,
    KEYCODE_D,
    KEYCODE_E,
    KEYCODE_F,
    KEYCODE_G,
    KEYCODE_H,
    KEYCODE_I,
    KEYCODE_J,
    KEYCODE_K,
    KEYCODE_L,
    KEYCODE_M,
    KEYCODE_N,
    KEYCODE_O,
    KEYCODE_P,
    KEYCODE_Q,
    KEYCODE_R,
    KEYCODE_S,
    KEYCODE_T,
    KEYCODE_U,
    KEYCODE_V,
    KEYCODE_W,
    KEYCODE_X,
    KEYCODE_Y,
    KEYCODE_Z,
    KEYCODE_COMMA,
    KEYCODE_PERIOD,
    KEYCODE_ALT_LEFT,
    KEYCODE_ALT_RIGHT,
    KEYCODE_SHIFT_LEFT,
    KEYCODE_SHIFT_RIGHT,
    KEYCODE_TAB,
    KEYCODE_SPACE,
    KEYCODE_SYM,
    KEYCODE_EXPLORER,
    KEYCODE_ENVELOPE,
    KEYCODE_ENTER,
    KEYCODE_DEL,
    KEYCODE_GRAVE,
    KEYCODE_MINUS,
    KEYCODE_EQUALS,
    KEYCODE_LEFT_BRACKET,
    KEYCODE_RIGHT_BRACKET,
    KEYCODE_BACKSLASH,
    KEYCODE_SEMICOLON,
    KEYCODE_APOSTROPHE,
    KEYCODE_SLASH,
    KEYCODE_AT,
    KEYCODE_NUM,
    KEYCODE_HEADSETHOOK,
    KEYCODE_FOCUS,
    KEYCODE_PLUS,
    KEYCODE_MENU,
    KEYCODE_NOTIFICATION,
    KEYCODE_SEARCH,
    KEYCODE_MEDIA_PLAY_PAUSE,
    KEYCODE_MEDIA_STOP,
    KEYCODE_MEDIA_NEXT,
    KEYCODE_MEDIA_PREVIOUS,
    KEYCODE_MEDIA_REWIND,
    KEYCODE_MEDIA_FAST_FORWARD,
    KEYCODE_MUTE,
    KEYCODE_PAGE_UP,
    KEYCODE_PAGE_DOWN,
    KEYCODE_PICTSYMBOLS,
    KEYCODE_SWITCH_CHARSET,
    KEYCODE_BUTTON_A,
    KEYCODE_BUTTON_B,
    KEYCODE_BUTTON_C,
    KEYCODE_BUTTON_X,
    KEYCODE_BUTTON_Y,
    KEYCODE_BUTTON_Z,
    KEYCODE_BUTTON_L1,
    KEYCODE_BUTTON_R1,
    KEYCODE_BUTTON_L2,
    KEYCODE_BUTTON_R2,
    KEYCODE_BUTTON_THUMBL,
    KEYCODE_BUTTON_THUMBR,
    KEYCODE_BUTTON_START,
    KEYCODE_BUTTON_SELECT,
    KEYCODE_BUTTON_MODE,
    KEYCODE_ESCAPE,
    KEYCODE_FORWARD_DEL,
    KEYCODE_CTRL_LEFT,
    KEYCODE_CTRL_RIGHT,
    KEYCODE_CAPS_LOCK,
    KEYCODE_SCROLL_LOCK,
    KEYCODE_META_LEFT,
    KEYCODE_META_RIGHT,
    KEYCODE_FUNCTION,
    KEYCODE_SYSRQ,
    KEYCODE_BREAK,
    KEYCODE_MOVE_HOME,
    KEYCODE_MOVE_END,
    KEYCODE_INSERT,
    KEYCODE_FORWARD,
    KEYCODE_MEDIA_PLAY,
    KEYCODE_MEDIA_PAUSE,
    KEYCODE_MEDIA_CLOSE,
    KEYCODE_MEDIA_EJECT,
    KEYCODE_MEDIA_RECORD,
    KEYCODE_F1,
    KEYCODE_F2,
    KEYCODE_F3,
    KEYCODE_F4,
    KEYCODE_F5,
    KEYCODE_F6,
    KEYCODE_F7,
    KEYCODE_F8,
    KEYCODE_F9,
    KEYCODE_F10,
    KEYCODE_F11,
    KEYCODE_F12,
    KEYCODE_NUM_LOCK,
    KEYCODE_NUMPAD_0,
    KEYCODE_NUMPAD_1,
    KEYCODE_NUMPAD_2,
    KEYCODE_NUMPAD_3,
    KEYCODE_NUMPAD_4,
    KEYCODE_NUMPAD_5,
    KEYCODE_NUMPAD_6,
    KEYCODE_NUMPAD_7,
    KEYCODE_NUMPAD_8,
    KEYCODE_NUMPAD_9,
    KEYCODE_NUMPAD_DIVIDE,
    KEYCODE_NUMPAD_MULTIPLY,
    KEYCODE_NUMPAD_SUBTRACT,
    KEYCODE_NUMPAD_ADD,
    KEYCODE_NUMPAD_DOT,
    KEYCODE_NUMPAD_COMMA,
    KEYCODE_NUMPAD_ENTER,
    KEYCODE_NUMPAD_EQUALS,
    KEYCODE_NUMPAD_LEFT_PAREN,
    KEYCODE_NUMPAD_RIGHT_PAREN,
    KEYCODE_VOLUME_MUTE,
    KEYCODE_INFO,
    KEYCODE_CHANNEL_UP,
    KEYCODE_CHANNEL_DOWN,
    KEYCODE_ZOOM_IN,
    KEYCODE_ZOOM_OUT,
    KEYCODE_TV,
    KEYCODE_WINDOW,
    KEYCODE_GUIDE,
    KEYCODE_DVR,
    KEYCODE_BOOKMARK,
    KEYCODE_CAPTIONS,
    KEYCODE_SETTINGS,
    KEYCODE_TV_POWER,
    KEYCODE_TV_INPUT,
    KEYCODE_STB_POWER,
    KEYCODE_STB_INPUT,
    KEYCODE_AVR_POWER,
    KEYCODE_AVR_INPUT,
    KEYCODE_PROG_RED,
    KEYCODE_PROG_GREEN,
    KEYCODE_PROG_YELLOW,
    KEYCODE_PROG_BLUE,
    KEYCODE_APP_SWITCH,
    KEYCODE_BUTTON_1,
    KEYCODE_BUTTON_2,
    KEYCODE_BUTTON_3,
    KEYCODE_BUTTON_4,
    KEYCODE_BUTTON_5,
    KEYCODE_BUTTON_6,
    KEYCODE_BUTTON_7,
    KEYCODE_BUTTON_8,
    KEYCODE_BUTTON_9,
    KEYCODE_BUTTON_10,
    KEYCODE_BUTTON_11,
    KEYCODE_BUTTON_12,
    KEYCODE_BUTTON_13,
    KEYCODE_BUTTON_14,
    KEYCODE_BUTTON_15,
    KEYCODE_BUTTON_16,
    KEYCODE_LANGUAGE_SWITCH,
    KEYCODE_MANNER_MODE,
    KEYCODE_3D_MODE,
    KEYCODE_CONTACTS,
    KEYCODE_CALENDAR,
    KEYCODE_MUSIC,
    KEYCODE_CALCULATOR,
    KEYCODE_ZENKAKU_HANKAKU,
    KEYCODE_EISU,
    KEYCODE_MUHENKAN,
    KEYCODE_HENKAN,
    KEYCODE_KATAKANA_HIRAGANA,
    KEYCODE_YEN,
    KEYCODE_RO,
    KEYCODE_KANA,
    KEYCODE_ASSIST,
    KEYCODE_BRIGHTNESS_DOWN,
    KEYCODE_BRIGHTNESS_UP,
    KEYCODE_MEDIA_AUDIO_TRACK,
    KEYCODE_SLEEP,
    KEYCODE_WAKEUP,
    KEYCODE_PAIRING,
    KEYCODE_MEDIA_TOP_MENU,
    KEYCODE_11,
    KEYCODE_12,
    KEYCODE_LAST_CHANNEL,
    KEYCODE_TV_DATA_SERVICE,
    KEYCODE_VOICE_ASSIST,
    KEYCODE_TV_RADIO_SERVICE,
    KEYCODE_TV_TELETEXT,
    KEYCODE_TV_NUMBER_ENTRY,
    KEYCODE_TV_TERRESTRIAL_ANALOG,
    KEYCODE_TV_TERRESTRIAL_DIGITAL,
    KEYCODE_TV_SATELLITE,
    KEYCODE_TV_SATELLITE_BS,
    KEYCODE_TV_SATELLITE_CS,
    KEYCODE_TV_SATELLITE_SERVICE,
    KEYCODE_TV_NETWORK,
    KEYCODE_TV_ANTENNA_CABLE,
    KEYCODE_TV_INPUT_HDMI_1,
    KEYCODE_TV_INPUT_HDMI_2,
    KEYCODE_TV_INPUT_HDMI_3,
    KEYCODE_TV_INPUT_HDMI_4,
    KEYCODE_TV_INPUT_COMPOSITE_1,
    KEYCODE_TV_INPUT_COMPOSITE_2,
    KEYCODE_TV_INPUT_COMPONENT_1,
    KEYCODE_TV_INPUT_COMPONENT_2,
    KEYCODE_TV_INPUT_VGA_1,
    KEYCODE_TV_AUDIO_DESCRIPTION,
    KEYCODE_TV_AUDIO_DESCRIPTION_MIX_UP,
    KEYCODE_TV_AUDIO_DESCRIPTION_MIX_DOWN,
    KEYCODE_TV_ZOOM_MODE,
    KEYCODE_TV_CONTENTS_MENU,
    KEYCODE_TV_MEDIA_CONTEXT_MENU,
    KEYCODE_TV_TIMER_PROGRAMMING,
    KEYCODE_HELP,
    KEYCODE_NAVIGATE_PREVIOUS,
    KEYCODE_NAVIGATE_NEXT,
    KEYCODE_NAVIGATE_IN,
    KEYCODE_NAVIGATE_OUT,
    KEYCODE_STEM_PRIMARY,
    KEYCODE_STEM_1,
    KEYCODE_STEM_2,
    KEYCODE_STEM_3,
    KEYCODE_DPAD_UP_LEFT,
    KEYCODE_DPAD_DOWN_LEFT,
    KEYCODE_DPAD_UP_RIGHT,
    KEYCODE_DPAD_DOWN_RIGHT,
    KEYCODE_MEDIA_SKIP_FORWARD,
    KEYCODE_MEDIA_SKIP_BACKWARD,
    KEYCODE_MEDIA_STEP_FORWARD,
    KEYCODE_MEDIA_STEP_BACKWARD,
    KEYCODE_SOFT_SLEEP,
    KEYCODE_CUT,
    KEYCODE_COPY,
    KEYCODE_PASTE,
    KEYCODE_SYSTEM_NAVIGATION_UP,
    KEYCODE_SYSTEM_NAVIGATION_DOWN,
    KEYCODE_SYSTEM_NAVIGATION_LEFT,
    KEYCODE_SYSTEM_NAVIGATION_RIGHT,
    KEYCODE_ALL_APPS,
    KEYCODE_REFRESH,
    KEYCODE_THUMBS_UP,
    KEYCODE_THUMBS_DOWN,
    KEYCODE_PROFILE_SWITCH,
    KEYCODE_VIDEO_APP_1,
    KEYCODE_VIDEO_APP_2,
    KEYCODE_VIDEO_APP_3,
    KEYCODE_VIDEO_APP_4,
    KEYCODE_VIDEO_APP_5,
    KEYCODE_VIDEO_APP_6,
    KEYCODE_VIDEO_APP_7,
    KEYCODE_VIDEO_APP_8,
    KEYCODE_FEATURED_APP_1,
    KEYCODE_FEATURED_APP_2,
    KEYCODE_FEATURED_APP_3,
    KEYCODE_FEATURED_APP_4,
    KEYCODE_DEMO_APP_1,
    KEYCODE_DEMO_APP_2,
    KEYCODE_DEMO_APP_3,
    KEYCODE_DEMO_APP_4,
  ];

  static final $core.List<RemoteKeyCode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 304);
  static RemoteKeyCode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const RemoteKeyCode._(super.value, super.name);
}

class RemoteDirection extends $pb.ProtobufEnum {
  static const RemoteDirection UNKNOWN_DIRECTION =
      RemoteDirection._(0, _omitEnumNames ? '' : 'UNKNOWN_DIRECTION');
  static const RemoteDirection START_LONG =
      RemoteDirection._(1, _omitEnumNames ? '' : 'START_LONG');
  static const RemoteDirection END_LONG =
      RemoteDirection._(2, _omitEnumNames ? '' : 'END_LONG');
  static const RemoteDirection SHORT =
      RemoteDirection._(3, _omitEnumNames ? '' : 'SHORT');

  static const $core.List<RemoteDirection> values = <RemoteDirection>[
    UNKNOWN_DIRECTION,
    START_LONG,
    END_LONG,
    SHORT,
  ];

  static final $core.List<RemoteDirection?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static RemoteDirection? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const RemoteDirection._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
