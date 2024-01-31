#!/bin/bash
yq service-profile.yaml
yq service-profile.yaml | yq 'del(.spec.routes[].responseClasses)' service-profile.yaml > service-profile-new.yaml
cat <<EOT >> service-profile-new.yaml
    - condition:
        method: POST
      name: POST [Default]
    - condition:
        method: GET
      name: GET [Default]
    - condition:
        method: PATCH
      name: PATCH [Default]
    - condition:
        method: PUT
      name: PUT [Default]
    - condition:
        method: HEAD
      name: HEAD [Default]
    - condition:
        method: OPTIONS
      name: OPTIONS [Default]
EOT
yq service-profile-new.yaml