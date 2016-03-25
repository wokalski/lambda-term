(*
 * lTerm.mli
 * ---------
 * Copyright : (c) 2011, Jeremie Dimino <jeremie@dimino.org>
 * Licence   : BSD3
 *
 * This file is a part of Lambda-Term.
 *)

(** Terminal manipulation *)

(** Note: for simplicity and of the implementation and reasonable behavior across setups,
    lambda term internally uses threads. For each terminal Lambda term uses two helper
    threads: one for reading inputs and one for the rendering.

    Only a few functions in this module might block the calling thread and are marked as
    such. These functions are always safe to be called from any thread, all other are not.

    Concretely, if you are using Lwt or Async, you can just send call blocking operations
    via a [Lwt_preemptive.detach] or [Thread_safe.block_on_async_exn].
*)

type t
(** Type of terminals. *)

(** {6 Creation} *)

module Blocking : sig
  type 'a t = private 'a
  val get : 'a t -> 'a
end

(** [create ?model (fd_in, fd_out)] creates a new terminal.

    - [model] is the type of the terminal, such as "rxvt" or "xterm". It defaults to the
    contents of the "TERM" environment variable, or to "dumb" if this one is not found. It
    is used to determine capabilities of the terminal, such as the number of colors.

    - [windows] indicates whether the terminal is a windows console (not mintty, rxvt,
    ...). It defaults to [Sys.win32].
*)
val create
  :  ?windows : bool
  -> ?model   : string
  -> Unix.file_descr * Unix.file_descr
  -> t Blocking.t

(** Restore the initial state and stop updating the terminal state. This does not close
    the underlying file descriptor. *)
val close : t -> unit Blocking.t

(** Enable/disable the terminal.

    When deactivated, signals are not processed and events are not returned until
    activated again. Note that when deactivated the terminal will be ignored by handlers
    of Ctrl+C, Ctrl+\ and Ctrl+Z. So you should ensure the terminal is in a good state
    before deactivating it.

    [set_active t false] will also allow for [t] to be garbage collected.
*)
val set_active : t -> bool -> unit

(** Warning: this function is blocking. It reset the status of all opened terminals. It is
    automatically called in an [Pervasives.at_exit] handler. You can use it in case of
    abnormal exit, for instance before printing an error message to ensure it is not
    erased by the by the [at_exit] handler. *)
val abort : unit -> unit

(** {6 Informations} *)

val model : t -> string
(** Returns the model of the terminal. *)

val default_model : string
(** Default terminal model, as given by the TERM environment variable *)

val colors : t -> int
(** Number of colors of the terminal. *)

val escape_time : t -> float
(** Time waited before returning the escape key. This is not used on
    windows. *)

val set_escape_time : t -> float -> unit
(** Set the time waited before returning the escape key. *)

val size : t -> LTerm_geom.size
(** Size of the terminal. *)

(** {6 Signals} *)

module Signals : sig
  module State : sig
    type t =
      (** The signal is not managed by lambda-term *)
      | Not_managed
      (** The signal will generate a [Signal] event on every terminal *)
      | Generate_event
      (** Handle it: INTR and QUIT restores terminal states and exit, TSTP restores
          terminal states and suspend. *)
      | Handled
    [@@deriving sexp]
  end

  (** Signals state *)
  type t =
    { intr : State.t (** Usually Ctrl+C *)
    ; quit : State.t (** Usually Ctrl+\ *)
    ; susp : State.t (** Usually Ctrl+Z *)
    }
  [@@deriving sexp]

  (** All fields are [State.Handled] *)
  val handled : t

  val get : unit -> t
  val set : t -> unit
end

(** {6 Events} *)

(** Start watching for inputs. Concretelly this means that A thread is started reading
    from the terminal input. *)
val set_watching : t -> bool -> unit

(** Reads and returns one event. The terminal should be in raw mode before calling this
    function, otherwise event will not be reported as they happen.

    If [no_text] is [true], [Text] events will be reported as multiple [Char] pr [Uchar]
    events.

    Note: When multiple [read_event] are pending on the same terminal, they will all
    return the same event when one becomes available. *)
val read_event : ?no_text:bool (* default: false *) -> t -> LTerm_event.t

(** {6 State change} *)

(** All state change take effects only when [sync] is called. *)

(** Sync with the terminal.

    [end_of_display] is an hint indicating to lambda term how many lines after the cursor
    position does the display extends to once synced. This is used in case the process
    receive a [TSTP], [INT] or [QUIT] signal. The lambda term signal handler will move
    down the cursor by [n] lines to leave things in a clean state.
*)
val sync : ?end_of_display:int -> t -> unit Blocking.t

module Screen : sig
  type t = Main | Alternative [@@deriving sexp]
end

module Mode : sig
  (** Terminal modes. These modes are preserved after resuming from a Ctrl+Z. *)
  type t =
    { echo    : bool (** If [true], characters are printed on screen             *)
    ; raw     : bool (** If [true], input is reported immediately                *)
    ; signals : bool (** If [true], signals are generated on INTR, QUIT and SUSP *)
    ; mouse   : bool (** If [true], mouse events are reported                    *)
    ; screen  : Screen.t
    }
  [@@deriving sexp, fields]

  (**
     {[
       { echo    = true
       ; raw     = false
       ; signals = true
       ; mouse   = false
       ; screen  = Main
       }
     ]}
  *)
  val default : t
end

val mode : t -> Mode.t
val set_mode : t -> Mode.t -> unit

(** Make the cursor visible. *)
val show_cursor : t -> unit

(** Make the cursor invisible. *)
val hide_cursor : t -> unit

val cursor_visible : t -> bool

(** Equivalent to:

    {[
      set_mode t Mode.default;
      show_cursor t;
    ]}
*)
val reset : t -> unit

val goto : t -> LTerm_geom.coord -> unit
(** [goto term coord] moves the cursor to the given coordinates. *)

val move : t -> rows:int -> cols:int -> unit
(** [move term rows columns] moves the cursor by the given number of
    lines and columns. Both [rows] and [columns] may be negavite. *)

val clear_screen : t -> unit
(** [clear_screen term] clears the entire screen. *)

val clear_screen_next : t -> unit
(** [clear_screen_next term] clears the screen from the cursor to
    the bottom of the screen. *)

val clear_screen_prev : t -> unit
(** [clear_screen_prev term] clears the screen from the cursor to
    the top of the screen. *)

val clear_line : t -> unit
(** [clear_line term] erases the current line. *)

val clear_line_next : t -> unit
(** [clear_line_next term] erases the current line from the cursor
    to the end of the line. *)

val clear_line_prev : t -> unit
(** [clear_line_prev term] erases the current line from the cursor
    to the beginning of the line. *)

(** {8 Printing} *)

val print : t -> string -> unit
val print_sub : t -> string -> pos:int -> len:int -> unit
val set_style : t -> LTerm_style.t -> unit

(** {8 Rendering} *)

val render : t -> ?old:LTerm_draw.matrix -> LTerm_draw.matrix -> unit
(** Render an offscreen array to the given terminal. [old] is the currently displayed
    matrix. If specified it is used to reduce the amount of text send to the
    terminal. *)

val print_box : t -> ?old:LTerm_draw.matrix -> LTerm_draw.matrix -> unit
(** [print_box term matrix] prints the contents of [matrix] starting
    at current cursor row. Note that when you have the choice
    between using {!fprints} and {!print_box} you should use
    {!print_box} because it works better under windows and is more
    efficient.

    The cursor is moved to the beginning of the last displayed
    line. *)

val print_box_with_newlines : t -> ?old:LTerm_draw.matrix -> LTerm_draw.matrix -> unit
(** [print_box term matrix] Same as {!print_box} but [matrix]
    may contains newline characters. It must contain one more column
    that the terminal (in case a line of the length of the terminal
    ends with a newline).

    The difference between {!print_box} and
    {!print_box_with_newlines} is that when the text is selected in
    the terminal, with {!print_box} it will always be a box with the
    dimensions of [matrix]. With {!print_box_with_newlines} it may
    contains lines longer than the width of the terminal.

    The contents of a line after the first newline character (if
    any) in a row of [matrix] is ignored. The rest of the line get
    the style of the newline character. *)

(** {6 Well known instances} *)

val std : t Lazy.t
(** Terminal using [Fd.stdin]. *)

(**/**)

val colors_of_term : string -> int
val bold_is_bright : string -> bool
