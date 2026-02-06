#!/usr/bin/env bash
set -euo pipefail

PROGNAME="$(basename "$0")"
SAMPLE_DIR="$(cd "$(dirname "$0")/.." && pwd)/sample/agents"

show_help() {
  cat <<EOF
Usage: $PROGNAME <command> [options]

Commands:
  add               Apply all manifests in sample/agents
  delete            Delete manifests in sample/agents (ignore-not-found)
  delete-all        Delete all GenericAgent resources in the namespace (requires confirmation unless --yes)
  recreate          Delete then add
  list              List GenericAgent resources (falls back to listing sample/agents files)
  help              Show this help

Options:
  -n, --namespace NAMESPACE   Operate on the given namespace (passed to kubectl)
  --yes                      Skip confirmation for destructive operations like delete-all

Examples:
  $PROGNAME add
  $PROGNAME delete
  $PROGNAME delete-all -n my-namespace --yes
  $PROGNAME recreate
  $PROGNAME list
EOF
}

if [[ $# -lt 1 ]]; then
  show_help
  exit 0
fi

CMD="$1"
shift || true

NAMESPACE=""
YES=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace)
      NAMESPACE="$2"; shift 2;;
    --yes)
      YES=true; shift;;
    -h|--help)
      show_help; exit 0;;
    *)
      echo "Unknown option: $1" >&2; show_help; exit 2;;
  esac
done

kubectl_args=()
if [[ -n "$NAMESPACE" ]]; then
  kubectl_args+=("-n" "$NAMESPACE")
fi

case "$CMD" in
  add)
    echo "Applying manifests from $SAMPLE_DIR"
    kubectl apply -R -f "$SAMPLE_DIR" "${kubectl_args[@]}";;

  delete)
    echo "Deleting manifests from $SAMPLE_DIR"
    kubectl delete -R -f "$SAMPLE_DIR" --ignore-not-found "${kubectl_args[@]}";;

  delete-all)
    if [[ "$YES" != true ]]; then
      read -r -p "Delete ALL GenericAgent resources in namespace '${NAMESPACE:-current}'? [y/N]: " ans
      case "$ans" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "Aborted."; exit 1;;
      esac
    fi
    echo "Deleting ALL GenericAgent resources in namespace '${NAMESPACE:-current}'"
    kubectl delete genericagents --all --ignore-not-found "${kubectl_args[@]}";;

  recreate)
    "$0" delete ${NAMESPACE:+-n "$NAMESPACE"}
    "$0" add ${NAMESPACE:+-n "$NAMESPACE"};;

  list)
    echo "Listing GenericAgent resources (namespace: ${NAMESPACE:-current})"
    if ! kubectl get genericagents -o wide "${kubectl_args[@]}"; then
      echo "Falling back to listing sample manifests in $SAMPLE_DIR"
      ls -1 "$SAMPLE_DIR" || true
    fi;;

  help|-h|--help)
    show_help;;

  *)
    echo "Unknown command: $CMD" >&2; show_help; exit 2;;
esac
