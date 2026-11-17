# __REPO_NAME__

Rendered manifests for **__ENV__**, watched by the __ENV__ cluster's Argo CD
(same role as `config-tde-dev5-dev` and friends).

- `argocd/apps/*.yaml`: the Argo CD Applications (app-of-apps)
- `apps/<app>/manifest.yaml`: plain rendered YAML, **written only by Kargo**. Don't edit it by hand.
