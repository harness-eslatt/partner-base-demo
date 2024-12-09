terraform {  
    required_providers {  
        harness = {  
            source = "harness/harness"
            version = "~> 0.30"
        }  
    }  
}

variable "account_id" {}
variable "pat" {}
variable "docker_username" {}
variable "docker_password" {}

variable "org_id" {
  default = "default"
}
variable "project_id" {
  default = "Base_Demo"
}

provider "harness" {
    endpoint            = "https://app.harness.io/gateway"
    account_id          = var.account_id
    platform_api_key    = var.pat
}

resource "harness_platform_connector_kubernetes" "instruqt" {
  org_id             = var.org_id
  project_id         = var.project_id
  identifier         = "instruqt_k8"
  name               = "Instruqt K8s"
  description        = "Connector to Instruqt workshop K8s cluster"
  
  inherit_from_delegate {
    delegate_selectors = ["helm-delegate"]
  }
}

resource "harness_platform_secret_text" "docker_username" {
  identifier                = "docker_username"
  name                      = "docker-username"
  org_id                    = var.org_id
  project_id                = var.project_id
  secret_manager_identifier = "harnessSecretManager"
  value_type               = "Inline"
  value                    = var.docker_username
}

resource "harness_platform_secret_text" "docker_password" {
  identifier                = "docker_password"
  name                      = "docker-pw"
  org_id                    = var.org_id
  project_id                = var.project_id
  secret_manager_identifier = "harnessSecretManager"
  value_type               = "Inline"
  value                    = var.docker_password
}

resource "harness_platform_connector_docker" "workshopdocker" {
  identifier  = "workshopdocker"
  name        = "Workshop Docker"
  org_id      = var.org_id
  project_id  = var.project_id
  type        = "DockerHub"
  url         = "https://index.docker.io/v2/"

  credentials {
    username_ref = harness_platform_secret_text.docker_username.identifier
    password_ref = harness_platform_secret_text.docker_password.identifier
  }

  depends_on = [
    harness_platform_secret_text.docker_username,
    harness_platform_secret_text.docker_password
  ]
}

resource "harness_platform_template" "compile_application" {
  identifier    = "Compile_Application"
  org_id        = var.org_id
  project_id    = var.project_id
  name          = "Compile Application"
  version       = "v0.1"
  is_stable     = true
  template_yaml = <<-EOT
template:
  name: "Compile Application"
  identifier: "Compile_Application"
  versionLabel: "v0.1"
  type: Step
  projectIdentifier: ${var.project_id}
  orgIdentifier: ${var.org_id}
  tags: {}
  spec:
    type: Run
    spec:
      connectorRef: ${harness_platform_connector_docker.workshopdocker.identifier}
      image: node:20-alpine
      shell: Sh
      command: |-
        cd frontend-app/harness-webapp
        npm install
        npm install -g @angular/cli

        mkdir -p ./src/environments
        echo "export const environment = {
          production: true,
          defaultApiUrl: "'"https://backend.sandbox.<+variable.sandbox_id>.instruqt.io"'",
          defaultSDKKey: "'"<+variable.sdk>"'"
        };" > ./src/environments/environment.prod.ts


        echo "export const environment = {
          production: true,
          defaultApiUrl: "'"https://backend.sandbox.<+variable.sandbox_id>.instruqt.io"'",
          defaultSDKKey: "'"<+variable.sdk>"'"
        };" > ./src/environments/environment.ts

        npm run build
  EOT

  depends_on = [
    harness_platform_connector_docker.workshopdocker
  ]
}

resource "harness_platform_connector_prometheus" "prometheus" {
  identifier         = "prometheus"
  name               = "Prometheus"
  org_id             = var.org_id
  project_id         = var.project_id
  description        = "Connector to Instruqt workshop Prometheus instance"
  url                = "http://prometheus-k8s.monitoring.svc.cluster.local:9090/"
  delegate_selectors = ["helm-delegate"]
}

resource "harness_platform_environment" "dev" {
  identifier  = "dev"
  name        = "Dev"
  org_id      = var.org_id
  project_id  = var.project_id
  type        = "PreProduction"
  tags        = []
  
  yaml = <<-EOT
environment:
  name: Dev
  identifier: dev
  tags: {}
  type: PreProduction
  orgIdentifier: ${var.org_id}
  projectIdentifier: ${var.project_id}
EOT
}

resource "harness_platform_environment" "prod" {
  identifier  = "prod"
  name        = "Prod"
  org_id      = var.org_id
  project_id  = var.project_id
  type        = "Production"
  tags        = []
  
  yaml = <<-EOT
environment:
  name: Prod
  identifier: prod
  tags: {}
  type: Production
  orgIdentifier: ${var.org_id}
  projectIdentifier: ${var.project_id}
EOT
}

resource "harness_platform_infrastructure" "k8s_dev" {
  identifier      = "k8s_dev"
  name            = "K8s Dev"
  org_id          = var.org_id
  project_id      = var.project_id
  env_id          = harness_platform_environment.dev.identifier
  type            = "KubernetesDirect"
  deployment_type = "Kubernetes"
  yaml            = <<-EOT
infrastructureDefinition:
  name: K8s Dev
  identifier: k8s_dev
  description: ""
  tags:
    owner: ed.slatt
  orgIdentifier: ${var.org_id}
  projectIdentifier: ${var.project_id}
  environmentRef: ${harness_platform_environment.dev.identifier}
  deploymentType: Kubernetes
  type: KubernetesDirect
  spec:
    connectorRef: ${harness_platform_connector_kubernetes.instruqt.identifier}
    namespace: default
    releaseName: release-<+INFRA_KEY>
  allowSimultaneousDeployments: true
EOT

  depends_on = [
    harness_platform_environment.dev,
    harness_platform_connector_kubernetes.instruqt
  ]
}

resource "harness_platform_service" "backend" {
  identifier  = "backend"
  name        = "backend"
  org_id      = var.org_id
  project_id  = var.project_id
  yaml = <<-EOT
service:
  name: backend
  identifier: backend
  orgIdentifier: ${var.org_id}
  projectIdentifier: ${var.project_id}
  serviceDefinition:
    spec:
      manifests:
        - manifest:
            identifier: backend
            type: K8sManifest
            spec:
              store:
                type: HarnessCode
                spec:
                  repoName: i201
                  gitFetchType: Branch
                  paths:
                    - harness-deploy/backend/manifests
                  branch: main
              valuesPaths:
                - harness-deploy/backend/values.yaml
              skipResourceVersioning: false
              enableDeclarativeRollback: false
      artifacts:
        primary:
          primaryArtifactRef: <+input>
          sources:
            - spec:
                connectorRef: ${harness_platform_connector_docker.workshopdocker.identifier}
                imagePath: edslatt/harness-demo
                tag: backend-latest
                digest: ""
              identifier: backend
              type: DockerRegistry
    type: Kubernetes
EOT

  depends_on = [
    harness_platform_connector_docker.workshopdocker
  ]
}