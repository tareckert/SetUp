# basis/bashrc.sh – aus ~/.bashrc geladen (interaktive Host-Shell)
export LESSHISTFILE=-

# Tab-Vervollständigung für ki: Befehle und Projektnamen
_ki_complete() {
    local cur=${COMP_WORDS[COMP_CWORD]} projects
    if [ "$COMP_CWORD" -eq 1 ]; then
        mapfile -t COMPREPLY < <(compgen -W "$(ki _commands 2>/dev/null)" -- "$cur")
    elif [ "$COMP_CWORD" -eq 2 ]; then
        case ${COMP_WORDS[1]} in
            open|shell|terminal|term|run|jobs|logs|stop|jupyter|clean|rm|mv|caches)
                projects=$(ki _projects 2>/dev/null)
                mapfile -t COMPREPLY < <(compgen -W "$projects" -- "$cur") ;;
            power) mapfile -t COMPREPLY < <(compgen -W "performance balanced" -- "$cur") ;;
            setup) mapfile -t COMPREPLY < <(compgen -W "list install remove reinstall files update" -- "$cur") ;;
        esac
    fi
}
complete -F _ki_complete ki
