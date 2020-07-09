# Short lived AWS Credentials for our Terraform Runs

When our [Terraform](https://terraform.io) configuration needs to provision resources in [AWS](https://aws.amazon.com/), it requires credentials to enable it to do so.

[Terraform Cloud](https://www.terraform.io/docs/cloud/index.html) and [Terraform Enterprise](https://www.terraform.io/docs/enterprise/index.html) provide a solution for encrypted, write-only storage of those credentials.

For organizations that use [Vault](https://vaultproject.io), we can alternatively leverage the [Vault Provider](https://www.terraform.io/docs/providers/vault/index.html) for Terraform and the [AWS Secrets Engine](https://www.vaultproject.io/docs/secrets/aws) in Vault to obtain just-in-time, short-lived AWS credentials for each Terraform run.

Because Terraform will need to communicate with Vault, it is recommended that the approach described here be utilized with Terraform Enterprise and not with Terraform Cloud. We don't want to expose our Vault clusters to the public Internet.

## Configure Vault

We will need to configure Vault with:
1. The AWS Secrets Engine.
1. A policy that enables Terraform Enterprise to consume the AWS Secrets Engine.
1. An Auth Method for Terraform Enterprise to authenticate with Vault.

### Create a set of AWS credentials for Vault

Vault will act as our trusted orchestrator of AWS credentials, and will need a set of credentials that enables it to provision AWS credentials. The credentials we are using have the following policy attached to them. For details on the permissions required for those credentials, please see the [AWS Secrets Engine](https://www.vaultproject.io/docs/secrets/aws) documentation.

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "ec2:DescribeInstances",
                "iam:GetRole",
                "iam:GetUser",
                "iam:AttachUserPolicy",
                "iam:CreateAccessKey",
                "iam:CreateUser",
                "iam:DeleteAccessKey",
                "iam:DeleteUser",
                "iam:DeleteUserPolicy",
                "iam:DetachUserPolicy",
                "iam:ListAccessKeys",
                "iam:ListAttachedUserPolicies",
                "iam:ListGroupsForUser",
                "iam:ListUserPolicies",
                "iam:PutUserPolicy",
                "iam:RemoveUserFromGroup"
            ],
            "Effect": "Allow",
            "Resource": "*"
        }
    ]
}
```

### Configure the AWS Secrets Engine

We will rely on some environment variables to facilitate our configuration.
* `VAULT_AWS_ACCESS_KEY_ID` - AWS Access Key ID for the Vault user.
* `VAULT_AWS_SECRET_ACCESS_KEY` - AWS Secret Access Key for the Vault user.
* `VAULT_AWS_REGION` - the AWS region that Vault will communicate with to provision AWS credentials. e.g. `us-west-2`
* `AWS_SECRETS_ENGINE` - the path for the AWS secrets engine. e.g. `aws`
* `VAULT_ROLE` - the role in Vault that Terraform will read from to obtain AWS credentials. e.g. `tfe-app1`
* `APPROLE_AUTH` - the path for the AppRole auth method. e.g. `approle`
* `TFE_APPROLE` - name of AppRole role for Terraform to authenticate with Vault. e.g. `tfe-role`
* `TFE_POLICY` - name of the policy to attach to the token when Terraform authenticates with Vault. e.g. `tfe-policy`

For example:
```
export VAULT_AWS_ACCESS_KEY_ID=<AWS_ACCESS_KEY_ID>
export VAULT_AWS_SECRET_ACCESS_KEY=<AWS_SECRET_ACCESS_KEY>
export VAULT_AWS_REGION=us-west-2
export AWS_SECRETS_ENGINE=aws
export VAULT_ROLE=ens-role
export APPROLE_AUTH=approle
export TFE_APPROLE=tfe-role
export TFE_POLICY=tfe-policy
```

Let's enable the AWS Secrets Engine.

```
vault secrets enable -path=${AWS_SECRETS_ENGINE} aws
```

Let's configure the AWS Secrets Engine.

```
vault write \
  ${AWS_SECRETS_ENGINE}/config/root \
  access_key=${VAULT_AWS_ACCESS_KEY_ID} \
  secret_key=${VAULT_AWS_SECRET_ACCESS_KEY} \
  region=${VAULT_AWS_REGION}
```

Let's configure a Vault role that maps to a set of permissions in AWS. When Terraform generates credentials, they are generated against this role.

```
vault write ${AWS_SECRETS_ENGINE}/roles/${VAULT_ROLE} credential_type=iam_user policy_document=-<<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "vaultTFESid",
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "iam:*",
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt"          
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF
```

### Test the AWS Secrets Engine

Let's pull a set of AWS credentials using the role we created.

```
vault read ${AWS_SECRETS_ENGINE}/creds/${VAULT_ROLE}
```

For example:

```
$ vault read ${AWS_SECRETS_ENGINE}/creds/${VAULT_ROLE}
Key                Value
---                -----
lease_id           aws/creds/tfe-app1/abcdefghijklmnopqrstuvwx
lease_duration     1h
lease_renewable    true
access_key         ABCDEFGHIJKLMNOPQRSTU
secret_key         abcdefghijklmnopqrstuvwxyz0123456790ABCD
security_token     <nil>
```

Let's revoke the lease for these credentials.

```
vault lease revoke <lease_id>
```

For example:

```
vault lease revoke aws/creds/tfe-app1/abcdefghijklmnopqrstuvwx
```

### Create Policy for Terraform

Let's create a policy that enables Terraform to consume the role we defined above.

```
vault policy write ${TFE_POLICY} -<<EOF
path "auth/token/create" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "${AWS_SECRETS_ENGINE}/creds/${VAULT_ROLE}" {
  capabilities = [ "read", "create" ]
}

EOF
```

### Enable AppRole auth method

We will have Terraform authenticate with Vault using the AppRole auth method. We could also provide Terraform with a token.

Let's enable the AppRole auth method if it isn't already enabled.

```
vault auth enable -path=${APPROLE_AUTH} approle
```

### Create AppRole for Terraform

Let's create an AppRole for Terraform to authenticate with Vault. This is a long-lived credential for Terraform to authenticate with Vault.

```
vault write auth/${APPROLE_AUTH}/role/${TFE_APPROLE} token_policies="${TFE_POLICY}" token_ttl=48h token_max_ttl=720h
```

Let's generate the Role ID and Secret ID to provide to Terraform. We will save these to environment variables so that we can feed them to our Terraform workspace.

```
export TFE_ROLE_ID=$(vault read -format=json auth/${APPROLE_AUTH}/role/${TFE_APPROLE}/role-id | jq -r .data.role_id)
```

```
export TFE_SECRET_ID=$(vault write -f -format=json auth/${APPROLE_AUTH}/role/${TFE_APPROLE}/secret-id | jq -r .data.secret_id)
```

Let's check the values we got back.

```
echo ${TFE_ROLE_ID}
echo ${TFE_SECRET_ID}
```

## Configure Terraform Workspace

### Fork this repo

Fork this repo or copy it to a version control system (VCS) provider that is configured in your Terraform Enterprise install.

### Create Terraform Workspace

[Create a Workspace](https://www.terraform.io/docs/cloud/getting-started/workspaces.html) in Terraform Enterprise and connect it to your VCS repo.

### Configure Terraform Variables

#### Terraform variables

The following variables must be configured in your Terraform workspace. The variables are documented in the [variables.tf](variables.tf) file.

* `owner`
* `ssh_key_name`
* `vault_addr`
* `vault_skip_tls_verify`
* `vault_role_id`
* `vault_secret_id`


#### Authenticating to Vault

Terraform will use the AppRole auth method we defined above in order to authenticate with Vault.

The `vault_role_id` and `vault_secret_id` variables will be marked **sensitive**. These and the other variables listed above can be set via the [UI](https://www.terraform.io/docs/cloud/workspaces/variables.html) or via the [API](https://www.terraform.io/docs/cloud/api/variables.html).

Below, we illustrate how this can be done with the Terraform API. In order to do this, we will need either a [Team Token](https://www.terraform.io/docs/cloud/users-teams-organizations/api-tokens.html#team-api-tokens) or [User Token](https://www.terraform.io/docs/cloud/users-teams-organizations/api-tokens.html#user-api-tokens) that has privileges to write to the workspace we are working with.

### Environment Variables

Let's define some environment variables to facilitate our work.

* `TFE_TEAM_TOKEN` - Terraform API Token for team that has privileges to write to the workspace we are working with.
* `TFE_ORG` - Name of the Organization in Terraform Enterprise.
* `TFE_ADDR` - The Terraform Enterprise address. e.g. `https://tfe.example.com`
* `TFE_WORKSPACE_NAME` - The name of the workspace in Terraform Enterprise. e.g. `tfe-demo-aws-with-vault-creds`

For example:

```
export TFE_TEAM_TOKEN=$(vault kv get -field=TFE_TEAM_TOKEN kv/tfe/tfe.example.com)
export TFE_ORG=$(vault kv get -field=TFE_ORG kv/tfe/tfe.example.com)
export TFE_ADDR=$(vault kv get -field=TFE_ADDR kv/tfe/tfe.example.com)
export TFE_WORKSPACE_NAME=tfe-demo-aws-with-vault-creds
```

Let's retrieve the workspace ID. We will need this to set our variables.

```
export WORKSPACE_ID=$(curl \
  --header "Authorization: Bearer $TFE_ORG_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  ${TFE_ADDR}/api/v2/organizations/${TFE_ORG}/workspaces | \
  jq -r ".data[] | select (.attributes.name==\"${TFE_WORKSPACE_NAME}\") | .id")
```

Let's check the Workspace ID.

```
echo $WORKSPACE_ID
```

#### Set `vault_role_id`

Let's prepare our payload for setting the `vault_role_id`.

```
cat <<EOF > payload_role_id.json
{
  "data": {
    "type":"vars",
    "attributes": {
      "key":"vault_role_id",
      "value":"${TFE_ROLE_ID}",
      "category":"terraform",
      "hcl":false,
      "sensitive":true
    }
  }
}
EOF
```

Let's set the `vault_role_id` Terraform variable.

```
curl \
  --header "Authorization: Bearer $TFE_TEAM_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  --request POST \
  --data @payload_role_id.json \
  ${TFE_ADDR}/api/v2/workspaces/${WORKSPACE_ID}/vars | jq -r .
```

Let's remove our payload.

```
rm -f payload_role_id.json
```

#### Set `vault_secret_id`

Let's prepare our payload for setting the `vault_secret_id`.

```
cat <<EOF > payload_secret_id.json
{
  "data": {
    "type":"vars",
    "attributes": {
      "key":"vault_secret_id",
      "value":"${TFE_SECRET_ID}",
      "category":"terraform",
      "hcl":false,
      "sensitive":true
    }
  }
}
EOF
```

Let's set the `vault_secret_id` Terraform variable.

```
curl \
  --header "Authorization: Bearer $TFE_TEAM_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  --request POST \
  --data @payload_secret_id.json \
  ${TFE_ADDR}/api/v2/workspaces/${WORKSPACE_ID}/vars | jq -r .
```

Let's remove our payload.

```
rm -f payload_secret_id.json
```

## Run Terraform

With everything in place, we're ready to run our Terraform workspace.
