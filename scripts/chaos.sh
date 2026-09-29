#!/bin/bash
# Chaos experiments for the demo. Run ./scripts/test-traffic.sh in another terminal first.
# Usage: ./scripts/chaos.sh pod-kill | backend-down | backend-up | fault-on | fault-off
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
  pod-kill)      # Kill every backend pod; the ReplicaSet controller recreates them
    kubectl delete pod -l app=backend --now
    kubectl get pods -l app=backend -w ;;
  backend-down)  # Sustained outage: frontend returns 503 until backend-up
    kubectl scale deploy/backend --replicas=0 ;;
  backend-up)
    kubectl scale deploy/backend --replicas=2
    kubectl rollout status deploy/backend ;;
  fault-on)      # Istio fault injection: 50% of frontend -> backend calls abort with HTTP 500
    kubectl apply -f k8s/chaos/fault-injection.yaml ;;
  fault-off)
    kubectl delete -f k8s/chaos/fault-injection.yaml --ignore-not-found ;;
  *)
    echo "Usage: $0 pod-kill | backend-down | backend-up | fault-on | fault-off"; exit 1 ;;
esac
