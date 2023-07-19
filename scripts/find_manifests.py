"""Search for Kubneretes manifests in the kubernetes/manifests/ directory."""

from pathlib import Path


def run() -> None:
    """Search for Kubneretes manifests in the kubernetes/manifests/ directory."""
    likely_manifests = [
        str(file)
        for file in Path("./kubernetes/manifests/").glob("**/*.yaml")
        if "apiVersion:" in file.read_text()  # File is likely a k8s manifests
        and not file.stem.startswith("_")  # Ignore manifests that start with _
    ]

    print("\n".join(likely_manifests))


if __name__ == "__main__":
    run()
