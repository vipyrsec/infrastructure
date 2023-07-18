import os
from pathlib import Path

potential_manifests = Path(".").glob("**/*.yaml")

likely_manifests = []

for file in potential_manifests:
    if "apiVersion:" in file.read_text():
    # File is likely a k8s manifests

        # Ignore manifests that start with _
        if not file.stem.startswith("_"):
            likely_manifests.append(str(file))

print("\n".join(likely_manifests))
