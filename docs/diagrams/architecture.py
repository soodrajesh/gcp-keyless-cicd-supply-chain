#!/usr/bin/env python3
"""Generates docs/img/architecture.svg (PNG via docs/diagrams/render.py)."""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from archlib import Diagram  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "img", "architecture.svg")

W, H = 1780, 1350
d = Diagram(W, H, "Keyless CI/CD and a signed supply chain: GitHub Actions to Cloud Run",
            "Workload Identity Federation pinned to one workflow file · Sigstore keyless signing · SBOM + SLSA provenance · verify before deploy · no stored credentials")

d.group(30, 100, 400, 680, "GitHub  ·  the repository", "#5f6368", dash=False, fill="#f8f9fa", label_w=260)
d.group(560, 100, 1110, 680, "Google Cloud project  ·  europe-west1", "#1a73e8", dash=False, fill="#f8faff", label_w=330)

d.node("pr", 130, 240, "Pull request", "git", "dev", "any branch or fork")
d.node("ci", 330, 240, "ci.yml", "pipeline", "dev", "lint · test · scan · build\nNO id-token: no cloud")
d.node("sig", 130, 430, "Sigstore", "shield", "security", "Fulcio cert + Rekor log\n(public-good instance)")
d.node("rel", 330, 430, "release.yml", "pipeline", "compute", "main only: build · gate ·\npush · sign · SBOM · SLSA")
d.node("dep", 330, 610, "deploy.yml", "pipeline", "compute", "verify -> deploy by digest\n(called by release, or manual)")

d.node("wif", 700, 430, "Workload Identity", "key", "security", "gate 1: repo + owner id\ngate 2: workflow file @ main")
d.node("pub", 1000, 300, "kcs-publisher", "user", "actor", "write to registry only")
d.node("dsa", 1000, 610, "kcs-deployer", "user", "actor", "service-scoped run.developer")
d.node("ar", 1300, 300, "Artifact Registry", "registry", "data", "immutable tags\nimage + signature + attestations")
d.node("run", 1300, 610, "keyless-demo", "run", "compute", "Cloud Run, private\nserved by digest")
d.node("rt", 1560, 610, "kcs-runtime", "user", "actor", "holds no roles")

d.edge("pr", "ci", "h", num=1, label="pull_request")
d.edge("rel", "sig", "h", num=2, label="keyless sign + attest")
d.edge("rel", "wif", "h", num=3, label="OIDC token")
d.edge("wif", "pub", "vh", num=4, label="only release.yml", sides=("t", "l"))
d.edge("pub", "ar", "h", num=5, label="push +\nsignatures")
d.path([(360, 610), (500, 610), (500, 440), (670, 440)], num=6, label="OIDC token", lab_at=(430, 598))
d.edge("wif", "dsa", "vh", num=7, label="only deploy.yml", sides=("b", "l"))
d.edge("dsa", "run", "h", num=8, label="deploy image@digest\nafter verify")
d.edge("run", "rt", "h")
d.path([(1330, 300), (1440, 300), (1440, 705), (330, 705), (330, 640)], num=9, label="cosign verify + attestation + provenance (read)", lab_at=(900, 693), dash=True)
d.path([(300, 640), (300, 660), (130, 660), (130, 460)], num=10, label="verify identity", lab_at=(215, 648))

d.badge(80, 830, "11", "#1e8e3e")
d.text(100, 835, "No service-account key, no stored secret: the repository has zero Actions secrets; its variables are identifiers only. Neither pull requests nor any other workflow can become a service account.", 12, "#3c4043")

d.band(30, 870, 1640, 120, "PROVEN LIVE BY DRILLS  ·  see docs/test-results.md", "#d93025", "#fff8f7")
d.text(60, 912, "A workflow file that is not in the bindings is refused for both identities · deploy.yml dispatched from a branch fails at auth · an UNSIGNED image and an image validly signed by a DIFFERENT identity are both refused", 12.5, "#3c4043")
d.text(60, 936, "at 'Verify signature' with production untouched · the genuine image passes the same workflow · re-pushing an existing tag is refused. NOT proven: a different repository being rejected by gate 1 (needs a second repo).", 12.5, "#3c4043")

d.legend(34, 1020, "Numbered flows", [
    ("1", "Pull requests run ci.yml, which has no id-token permission: it cannot obtain a Google token even from a fork"),
    ("2", "release.yml signs the pushed digest with its job identity (Fulcio certificate, Rekor entry) and attaches a CycloneDX SBOM and SLSA provenance"),
    ("3", "The build job presents GitHub's OIDC token to Google STS; the provider's condition accepts only this repository (by numeric id) and owner"),
    ("4", "Only the principal release.yml@refs/heads/main may impersonate kcs-publisher"),
    ("5", "The publisher pushes the image; tags are immutable, so a tag can never be repointed"),
    ("6", "deploy.yml presents its own OIDC token; its job_workflow_ref is deploy.yml@refs/heads/main"),
    ("7", "Only that principal may impersonate kcs-deployer, whose roles are scoped to the one service and the registry (read)"),
    ("8", "The deployer ships image@digest, then smoke-tests the private service with an identity token"),
    ("9", "Before deploying, deploy.yml verifies signature, SBOM attestation and SLSA provenance against the expected workflow identity"),
    ("10", "Verification pins certificate identity and issuer, so a valid signature from any other identity is refused"),
], w=1720)
d.key(34, 1300)
d.save(OUT)
