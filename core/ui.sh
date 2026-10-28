# core/ui.sh – Bausteine für Menüs und Dialoge (gum, mit Notfallmodus ohne gum)
#
# Regel: Bildschirmausgaben gehen nach stderr. stdout gehört den Rückgabewerten, damit
# Aufrufe wie  p=$(ui_choose …)  nur die Auswahl enthalten.

UI_ACC="#CC7832" UI_FG="#A9B7C6" UI_DIM="#808080" UI_BG="#2B2B2B" UI_ERR="#F2777A" UI_OK="#6A8759"
export GUM_CHOOSE_CURSOR_FOREGROUND=$UI_ACC GUM_CHOOSE_HEADER_FOREGROUND=$UI_DIM \
       GUM_CHOOSE_ITEM_FOREGROUND=$UI_FG GUM_CHOOSE_SELECTED_FOREGROUND=$UI_ACC \
       GUM_FILTER_INDICATOR_FOREGROUND=$UI_ACC GUM_FILTER_MATCH_FOREGROUND=$UI_ACC \
       GUM_FILTER_PROMPT_FOREGROUND=$UI_ACC GUM_FILTER_HEADER_FOREGROUND=$UI_DIM \
       GUM_FILTER_TEXT_FOREGROUND=$UI_FG GUM_FILTER_CURSOR_TEXT_FOREGROUND=$UI_ACC \
       GUM_INPUT_CURSOR_FOREGROUND=$UI_ACC GUM_INPUT_PROMPT_FOREGROUND=$UI_ACC \
       GUM_INPUT_HEADER_FOREGROUND=$UI_DIM \
       GUM_CONFIRM_PROMPT_FOREGROUND=$UI_FG GUM_CONFIRM_SELECTED_BACKGROUND=$UI_ACC \
       GUM_CONFIRM_SELECTED_FOREGROUND=$UI_BG GUM_CONFIRM_UNSELECTED_BACKGROUND="#3C3F41" \
       GUM_CONFIRM_UNSELECTED_FOREGROUND=$UI_FG \
       GUM_FILE_CURSOR_FOREGROUND=$UI_ACC GUM_FILE_HEADER_FOREGROUND=$UI_DIM

HAVE_GUM=0
command -v gum >/dev/null 2>&1 && HAVE_GUM=1

INDENT="  "
set_indent() {   # Einrückung, damit eine Liste mittig steht
    local w=0 x pad cols
    for x in "$@"; do [ "${#x}" -gt "$w" ] && w=${#x}; done
    cols=$(tput cols 2>/dev/null || echo 80)
    pad=$(( (cols - w - 2) / 2 ))
    [ $pad -lt 2 ] && pad=2
    printf -v INDENT '%*s' "$pad" ''
}
clear_screen() { printf '\e[H\e[2J\e[3J' >&2; }   # inkl. Scrollback
pause() { printf '\n%s' "${INDENT}Weiter mit beliebiger Taste …" >&2; read -r -s -n 1 _ </dev/tty; printf '\n' >&2; }
say_err() {
    if [ $HAVE_GUM = 1 ]; then gum style --foreground "$UI_ERR" "$INDENT$*" >&2
    else printf '%s! %s\n' "$INDENT" "$*" >&2; fi
}
say_ok() {
    if [ $HAVE_GUM = 1 ]; then gum style --foreground "$UI_OK" "$INDENT$*" >&2
    else printf '%s%s\n' "$INDENT" "$*" >&2; fi
}

ui_choose() {   # ui_choose <überschrift> <eintrag…> → gewählter Eintrag
    local header=$1 i n; shift
    set_indent "$header" "$@"
    if [ $HAVE_GUM = 1 ]; then
        gum choose --cursor "$INDENT› " --header "${header:+$INDENT$header}" --height "$(( $# + 1 ))" -- "$@"
        return
    fi
    [ -n "$header" ] && printf '\n%s%s\n' "$INDENT" "$header" >&2
    i=1; for n in "$@"; do printf '%s%2d) %s\n' "$INDENT" "$i" "$n" >&2; i=$((i + 1)); done
    read -r -p "${INDENT}Nummer (Enter = zurück): " n </dev/tty || return 1
    [[ $n =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le $# ] || return 1
    printf '%s\n' "${!n}"
}
ui_multi() {   # ui_multi <überschrift> <vorausgewählt, durch | getrennt> <eintrag…> → Auswahl zeilenweise
    local header=$1 pre=$2 args=() x; shift 2
    set_indent "$header" "$@"
    if [ $HAVE_GUM = 0 ]; then printf '%s\n' "$@"; return; fi
    local IFS='|'
    for x in $pre; do [ -n "$x" ] && args+=(--selected "$x"); done
    unset IFS
    gum choose --no-limit --cursor "$INDENT› " --header "$INDENT$header" --height "$(( $# + 1 ))" "${args[@]}" -- "$@"
}
ui_filter() {   # ui_filter <überschrift> → Auswahl aus stdin (Tippen filtert)
    if [ $HAVE_GUM = 1 ]; then
        gum filter --header "$1" --placeholder "Tippen zum Filtern …" --prompt "› " --height 20
        return
    fi
    local lines=(); mapfile -t lines
    ui_choose "$1" "${lines[@]}"
}
ui_input() {   # ui_input <überschrift> <platzhalter> [vorgabe] → Eingabe
    local v
    if [ $HAVE_GUM = 1 ]; then
        gum input --header "$INDENT$1" --placeholder "$2" --value "${3:-}" --prompt "$INDENT› " --char-limit 300
        return
    fi
    read -r -e -p "$INDENT$1: " -i "${3:-}" v </dev/tty || return 1
    printf '%s\n' "$v"
}
ui_confirm() {   # ui_confirm <frage> [no] [sekunden] → 0 = ja; bei Zeitablauf nein
    local a args=(--affirmative "Ja" --negative "Nein")
    [ "${2:-}" = no ] && args+=(--default=false)
    [ -n "${3:-}" ] && args+=(--timeout "${3}s")
    if [ $HAVE_GUM = 1 ]; then gum confirm "$INDENT$1" "${args[@]}"; return; fi
    if [ -n "${3:-}" ]; then read -r -t "$3" -p "$INDENT$1 [j/N] " a </dev/tty || return 1
    else read -r -p "$INDENT$1 [j/N] " a </dev/tty || return 1; fi
    [[ $a =~ ^[jJyY] ]]
}
ui_pager() { if [ $HAVE_GUM = 1 ]; then gum pager; else less -R; fi; }

ui_box() {   # ui_box <zeile…> – mittiger Kasten (Menükopf)
    local cols w=0 x ml lines=()
    for x in "$@"; do [ -n "$x" ] && lines+=("$x"); done
    cols=$(tput cols 2>/dev/null || echo 80)
    for x in "${lines[@]}"; do [ "${#x}" -gt "$w" ] && w=${#x}; done
    ml=$(( (cols - w - 8) / 2 )); [ $ml -lt 0 ] && ml=0
    if [ $HAVE_GUM = 1 ]; then
        gum style --border rounded --border-foreground "$UI_ACC" --foreground "$UI_FG" --align center \
            --padding "0 3" --margin "1 $ml" "${lines[@]}" >&2
    else
        printf '\n' >&2; for x in "${lines[@]}"; do printf '%*s%s\n' "$ml" '' "$x" >&2; done; printf '\n' >&2
    fi
}
