## What is "yq"?

The name "yq" is used by at least two different projects to process YAML (and other formats):

1. **Mike Farah’s yq**: written in Go. A widely used tool that supports not only YAML, but also JSON, XML, CSV, TOML, Java-style properties, etc. ([GitHub][1])
2. **Andrey Kislyuk’s "yq"** (and Python variants) which essentially shells out to `jq` internally: converts YAML to JSON, processes it, and sometimes converts back. 🔄 ([Unix & Linux Stack Exchange][2])

---

## What does "Mike Farah yq v4+" mean?

It refers to version 4 (and newer) of Mike Farah’s tool. It introduces significant changes compared to earlier versions and relative to the other "yq" variant. Some notable aspects:

---

## Comparison: Mike Farah’s yq v4+ vs other yq implementations

| Feature                                                | Mike Farah’s yq v4+                                                                                                                                                                                              | Other variant (e.g. Kislyuk)                                                                                         |
| ------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| **Language / implementation**                          | Go. Stand‑alone static binaries. ([GitHub][1])                                                                                                                                                                   | Python + jq (and other dependencies). ([Unix & Linux Stack Exchange][2])                                             |
| **Supported formats**                                  | YAML, JSON, XML, CSV, TOML, properties, etc. ([GitHub][1])                                                                                                                                                      | Mainly YAML → JSON → (jq) → output; potentially fewer integrated formats. ([Unix & Linux Stack Exchange][2])        |
| **Expression / command syntax**                        | Version 4 adds a more modern, flexible syntax with more operators and performance improvements. ([GitHub][3])                                                                                                   | Generally follows `jq` syntax, since many operations are delegated to jq.                                            |
| **In-place editing while preserving comments**         | A strong advantage: can edit YAML files in place while preserving comments, formatting, spacing, etc. ([mikefarah.gitbook.io][4])                                                                                | Less guarantee of exact comment / formatting preservation due to repeated YAML ↔ JSON conversions.                  |
| **Availability / portability**                         | Prebuilt binaries for multiple OSes; integrates well in modern tooling. ([GitHub][1])                                                                                                                           | Requires Python + jq, possibly more dependencies.                                                                    |
| **Compatibility / learning curve**                     | 4+ introduces breaking changes vs v2/v3; some flags/syntax changed or removed. Learning curve if you come from older versions. ([mikefarah.gitbook.io][4])                                                      | If you already know jq the curve can be smaller, but you may miss yq‑specific features from Mike Farah’s version.    |

---

## Conclusion

In short: **Mike Farah’s yq v4+** is generally more powerful, feature‑rich, modern, better maintained, and geared toward real‑world YAML (and mixed‑format) workflows, with safe in‑place edits and better preservation of layout and comments. The “simpler” yq variants can be fine if you only need something minimal, already know jq, and do not care about retaining comments or formatting.


[1]: https://github.com/mikefarah/yq?utm_source=chatgpt.com "mikefarah/yq: yq is a portable command-line YAML ... - GitHub"
[2]: https://unix.stackexchange.com/questions/774082/executing-yq-but-jq-gets-executed?utm_source=chatgpt.com "debian - Executing `yq`, but `jq` gets executed"
[3]: https://github.com/mikefarah/yq/releases?utm_source=chatgpt.com "Releases · mikefarah/yq"
[4]: https://mikefarah.gitbook.io/yq?utm_source=chatgpt.com "yq | yq"
