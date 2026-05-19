# Lokalt utviklingsmiljø for Team Holmes — watson-admin-api
#
# Kjøremodus: Hybrid
#   - Infrastruktur (postgres, mock-oauth2-server) kjører i kind (k8s)
#   - watson-admin-api kjører som lokal prosess via ./gradlew bootRun
#
# Avhengigheter:
#   kind:    https://kind.sigs.k8s.io/docs/user/quick-start/#installation
#   tilt:    https://docs.tilt.dev/install.html
#   kubectl: https://kubernetes.io/docs/tasks/tools/

# Infrastruktur i kind
k8s_yaml([
    'k8s/watson-admin-api/postgres.yaml',
    'k8s/watson-admin-api/mock-oauth2-server.yaml',
])

k8s_resource(
    'postgres',
    port_forwards=['5432:5432'],
    labels=['infra'],
)

k8s_resource(
    'mock-oauth2-server',
    port_forwards=['8090:8090'],
    labels=['infra'],
)

# watson-admin-api kjører lokalt som long-running prosess.
# Manuell restart via Tilt UI eller: tilt trigger watson-admin-api
local_resource(
    'watson-admin-api',
    serve_cmd='cd ../watson-admin-api && SPRING_PROFILES_ACTIVE=local ./gradlew bootRun',
    resource_deps=['postgres', 'mock-oauth2-server'],
    readiness_probe=probe(
        http_get=http_get_action(port=8080, path='/actuator/health'),
        period_secs=5,
        failure_threshold=15,
    ),
    links=[
        link('http://localhost:8080/swagger-ui/index.html', 'Swagger UI'),
        link('http://localhost:8080/actuator/health', 'Health'),
        link('http://localhost:8090', 'mock-oauth2-server'),
    ],
    labels=['backend'],
)
