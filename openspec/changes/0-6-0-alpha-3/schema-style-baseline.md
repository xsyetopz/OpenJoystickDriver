# Schema style baseline

Failures of `Tests/RepositoryScripts/test_schema_style.py` before task 7.2. One failure is one rule broken at one JSON pointer, so a description can fail more than once.

| Schema file | Failures |
| --- | ---: |
| access-grants.schema.json | 11 |
| cli-output.schema.json | 67 |
| controller-patch.schema.json | 5 |
| controller.schema.json | 45 |
| crosswalk.schema.json | 7 |
| endpoint.schema.json | 31 |
| error-codes.schema.json | 5 |
| mod-package.schema.json | 10 |
| profile.schema.json | 12 |
| protocol-description.schema.json | 49 |
| report.schema.json | 10 |
| service-listener-failure.schema.json | 6 |
| settings.schema.json | 18 |
| virtual-device.schema.json | 7 |
| vocabulary.schema.json | 4 |
| **Total** | **287** |

By rule: more than one sentence 109, over 120 characters 78, validator wording 26, ojd command 24, `$comment` 23, path 16, Swift type or code 7, error code 4. Ending without a period fails none.
