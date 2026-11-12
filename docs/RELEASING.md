# Releasing

A release is a tag. Pushing a `v*` tag runs [`.github/workflows/release.yml`](../.github/workflows/release.yml): it first proves the release path against a throwaway registry, then publishes `ghcr.io/<owner>/<repo>:<version>` with an SBOM, SLSA provenance, a keyless cosign signature and a GitHub attestation, and verifies all of them. Nothing is published by a merge or a pull request.

> **Publishing is locked.** The workflow builds and publishes only the `base` target: no Claude Code, no plugin (decided 2026-11-10, [PRODUCT-IMAGE.md](PRODUCT-IMAGE.md)); its acceptance job fails if `base` contains either. The publish job runs only when the repository variable `PUBLISH_IMAGE` is `true`. Until then a tag runs the acceptance job against a throwaway registry and publishes nothing.

## Cut a release

1. In a pull request, move "Unreleased" in [CHANGELOG.md](../CHANGELOG.md) under the new version.
2. Tag the merge commit and push the tag:

   ```bash
   git tag -s v0.1.0 -m "v0.1.0"   # use -a if you do not sign tags
   git push origin v0.1.0
   ```

3. Watch the workflow. Without `PUBLISH_IMAGE` only the acceptance job runs; the publish job shows as skipped. A new package is **private** at first: after the first publish, make it public in the package settings (irreversible) and check it is linked to the repository.
4. Run the verification below once from a machine that has no trust in the workflow.

## Verify an image

```bash
cosign verify ghcr.io/OWNER/REPO:0.1.0 \
  --certificate-identity-regexp '^https://github.com/OWNER/REPO/\.github/workflows/release\.yml@refs/tags/v.+$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

gh attestation verify oci://ghcr.io/OWNER/REPO:0.1.0 --repo OWNER/REPO
docker buildx imagetools inspect ghcr.io/OWNER/REPO:0.1.0 --format '{{json .SBOM}}'
```

In production, pin the image by digest (`ghcr.io/OWNER/REPO@sha256:...`).

## Notes

- Signatures and attestations are written to a public transparency log, so the workflow's identity is public. The repository is public.
- Do not create a GitHub Release by hand without signed assets: OpenSSF Scorecard's Signed-Releases check scores an unsigned release 0, and no release at all as not applicable.
- The acceptance job signs with a throwaway key and skips the transparency log, so it can run on every pull request. What only a tag exercises is the keyless identity and the attestation; the last step of the publish job verifies both.
