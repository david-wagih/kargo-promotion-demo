# platform-config (dev5)

Single source of truth for dev5's Kubernetes config.

```
base/                         shared manifests (third-party images pinned here, bumped by Renovate)
overlays/dev|staging|prod     per-environment differences
argocd-preview/               Argo CD Applications rendered by argocd-diff-preview on every PR
```

**Nobody pushes to the `env/dev` / `env/staging` / `env/prod` branches by hand.**
Kargo watches this folder plus the demo-app image on GHCR, bundles both into a
*Freight*, renders `overlays/<env>`, and commits the result to the env branch that
the env's own Argo CD watches.
