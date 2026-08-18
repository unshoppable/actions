# unshoppable/actions

Shared GitHub Actions for the medconomy repositories (`app-framework`, `grouper-api`,
`medcoding-model`). Reference them from the default branch:

```yaml
- uses: unshoppable/actions/actions/<name>@master
```

## Actions

| Action | Purpose |
| --- | --- |
| `append-env` | Appends variables from a JSON file to `/etc/environment`. |
| `claude-pr-review` | Runs the Dr. Claude review agent on a PR, archives its tool stream, fails when no review was posted. |
| `cloud-run-deploy` | Applies a Cloud Run service or job manifest, optionally opening the service to unauthenticated callers. |
| `deploy-notification` | Posts a deployment outcome to Discord, including the deployed commit subject. |
| `docker-build-push` | Builds a Docker image and pushes it to Artifact Registry under one or more tags. |
| `docker-image-exists` | Reports whether an exact image tag already exists in Artifact Registry. |
| `gcp-auth` | Authenticates to GCP via Workload Identity Federation or a service account key. |
| `gomplate` | Renders a gomplate template from merged JSON config files. |
| `merge` | Merges one branch into another and pushes the result. |
| `node-npm-install` | Sets up Node via Volta and installs dependencies with a cached `npm ci`. |

## Deployment pipeline

The GCP deploy actions compose in this order — each expects the previous one's side effects:

```yaml
- uses: unshoppable/actions/actions/gcp-auth@master          # authenticates gcloud
- uses: unshoppable/actions/actions/docker-image-exists@master # id: image -> outputs.exists
- uses: unshoppable/actions/actions/docker-build-push@master   # if: steps.image.outputs.exists == 'false'
- uses: unshoppable/actions/actions/gomplate@master            # renders the Cloud Run manifest
- uses: unshoppable/actions/actions/cloud-run-deploy@master    # applies it
- uses: unshoppable/actions/actions/deploy-notification@master # if: always()
```

`docker-image-exists` is a separate action rather than part of `docker-build-push` because callers
need its verdict before the build: `app-framework` skips its Nx build and Sentry source-map upload on
an existing image, and `grouper-api` retags the existing image instead of rebuilding.
