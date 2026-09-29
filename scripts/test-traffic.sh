#!/bin/bash
# Continuous load generator through the Istio IngressGateway (single North-South entry point).
# Usage: ./scripts/test-traffic.sh [path]   (default: /api/data)
PATH_TO_HIT="${1:-/api/data}"

GATEWAY_URL=$(kubectl -n istio-system get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
if [ -z "$GATEWAY_URL" ]; then
  GATEWAY_URL=$(kubectl -n istio-system get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
fi
if [ -z "$GATEWAY_URL" ]; then
  GATEWAY_URL="localhost:8080"
  echo "Warning: LoadBalancer not found. Using $GATEWAY_URL (kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80)."
fi
echo "Targeting http://$GATEWAY_URL$PATH_TO_HIT"

counter=1
while true; do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$GATEWAY_URL$PATH_TO_HIT" || echo "000")
  if [ "$CODE" = "200" ]; then COLOR="\033[32m"; else COLOR="\033[31m"; fi
  echo -e "$(date +%H:%M:%S) Request #$counter -> ${COLOR}HTTP $CODE\033[0m"
  counter=$((counter + 1))
  sleep 0.2
done
