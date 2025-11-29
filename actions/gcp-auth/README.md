# GCP Authentication Action

This GitHub Action provides a standardized way to authenticate with Google Cloud Platform, set up a service account, and configure the Google Cloud SDK in your workflows.

## Usage

```yaml
- name: Authenticate with GCP
  uses: ./.github/actions/gcp-auth
  with:
    gcp_credentials: ${{ secrets.GCP_CREDENTIALS }}
    service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}
    setup_cloud_sdk: 'true'
```

## Inputs

| Input             | Description                        | Required | Default |
| ----------------- | ---------------------------------- | -------- | ------- |
| `gcp_credentials` | GCP credentials JSON               | Yes      | -       |
| `service_account` | Service account email              | Yes      | -       |
| `setup_cloud_sdk` | Whether to set up Google Cloud SDK | No       | `true`  |

## Outputs

This action creates the following environment variables:

- `GCLOUD_CREDENTIALS_FILE_PATH`: Path to the copied credentials file (tmp/gcloud_credentials.json)

## Example

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Authenticate with GCP
        uses: ./.github/actions/gcp-auth
        with:
          gcp_credentials: ${{ secrets.GCP_CREDENTIALS }}
          service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}

      - name: Deploy to GCP
        run: |
          # Your deployment steps here
          # Can use $GCLOUD_CREDENTIALS_FILE_PATH for accessing credentials
```

## What This Action Does

1. Authenticates to Google Cloud using the provided credentials
2. Activates the specified service account
3. Sets the active service account for gcloud commands
4. Copies the credentials to a known location (tmp/gcloud_credentials.json)
5. Optionally sets up the Google Cloud SDK
