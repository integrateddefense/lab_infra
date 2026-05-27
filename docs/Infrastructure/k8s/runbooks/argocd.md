# ArgoCD Run Book

## Pre Requisites

This runbook assumes you have run [the k8s playbook](../../../../ansible/playbooks/kubernetes.yml) and successfully navigated to the ArgoCD GUI via a web browser.

## Troubleshooting Note

Ensure you select a different hostname for your ArgoCD UI and your ArgoCD API and configure your routes accordingly.

For example, creating an HTTPRoute a GRPCRoute to argo.domain.local will cause the Cilium CNI to drop all traffic, as it cannot definitively route HTTP traffic based on the conflicting specifications.

However, configuring an HTTPRoute for argo.domain.local and a GRPCRoute for argo-api.domain.local will allow it to pass traffic.

## Step 1 - Initial Setup

This step covers the initial application setup to gain access to Argo.

`kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`

Don't forget to use `--kubeconfig` if the kubeconfig that talos generated isn't in the default location. The command above will output the initial admin password, stored in the argocd-initial-admin-secret k8s Secret object, in plaintext.

The default admin username is `admin`.

Once logged in, it's recommended to immediately change the default admin password, delete the initial-password Secret, and vault the new password with ansible.

Next - configure projects. Projects are similar to namespaces, in that they control which applications in ArgoCD get access to which resources, and which users get access to which applications.

## Step 2 - GitLab Integration

The accepted pattern for integrating with GitLab repositories is to use Deploy Tokens, available via the Project > Settings > Repository > Deploy tokens menu.

Deploy tokens are read-only; even if misconfigured, a deploy token will never grant write privileges to the code base. Make sure your deploy token is configured with read_repository at minimum.

Once you have the token, go to Settings > Repositories > + Connect Repo. The Deploy Token username and password go in the username and password fields. Make sure you select the correct project as well - if your application is in a project that does not have any valid connected repositories, ArgoCD will submit an anonymous request to your GitLab server which will likely be denied unless the project is Public.

## Step 3 - App-of-Apps Deployment

The deployment is a one-time manual deploy. Afterwards, argocd will manage itself via the manifest located in the argocd folder.

There are two files that need to be available for the deployment to work:

1) app-of-apps.yaml - this is the main manifest that allows ArgoCD to manage applications dynamically. It provides indirect references to the applications that need to be deployed via argo application manifests.
2) argocd.yaml - this is the application manifest for argocd itself. It provides a direct reference to the source that argocd should use, where to deploy the application, any Kustomize patches that need to be implemented, and how Argo should handle maintaining the application state if it starts to differ.

Once app-of-apps.yaml is deployed, Argo will start searching in the repo referenced by `spec:source:repoURL` at the path specified by `spec:source:path` to find application manifests to deploy. It will find argocd.yaml and take control of the existing Argo deployment. It will also locate any additional application manifests and deploy those based on their specifications.

New applications only need to have their manifest included in the appropriate directory and pushed to main. Changes to existing applications, such as upgrading to a new version, requires changing `spec:source:targetRevision` in the application manifest and pushing to main. Argo handles the rest.

To apply the app of apps configuration, use the following command:

``` shell
kubectl apply -f <path to manifest>/app-of-apps.yaml
```

Don't forget `--kubeconfig` if you store it in a non-default location.

## Step 4 - Identity Integration and RBAC Configuration

Note: This step is not necessary in DR scenarios. Once the app-of-apps manifest is deployed in Step 3, these configurations will be automatically applied based on the specification stored in git.

ArgoCD includes two default roles:

- role:admin - basically a god role. Grants access to everything everywhere with no restrictions.
- role:readonly - Lets you read everything every where. No project restrictions.

There's also a third pseudo role - role:none - that's useful for explicitly denying any permissions.

Configuring permissions occurs in two places:

- AppProject Manifest - Directly inside the manifest, define project-scoped roles referenced with `proj:<project name>:<role name>`, and the resulting allowed/denied actions and resources using Casbin format statements.
- `argocd-rbac-cm` ConfigMap - usually as a kustomize or other patch, define globally scoped permissions and role bindings.

The model that worked best for me is to define project-scoped roles in the AppProject manifest, and then the AD group to project-scoped role mapping in a ConfigMap patch. As evidenced in the subsystem diagram, I end up duplicating a good few role configurations between projects, but it keeps things nicely separated without overcomplicating the kustomize patch.

There are two roles per project:

- `role:proj:<project-name>:developer`: This role is intended for DevSecOps personnel. It's able to read logs and manipulate applications within the project and related application components.
- `role:proj:<project-name>:readonly`: This role is intended for help desk or observability personnel. It's only able to read logs and see the status of applications within the project.

There's also a global administrator role defined in the ConfigMap patch:

- `role:kb-admin`: My replacement for the default admin role. This role is scoped to only allow access to argocd as a platform and not to the underlying applications in the projects. It manages clusters, projects, repositories, certificates, etc., and can review logs across the entire platform.
