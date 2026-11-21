# Protected Content

SVGs stay unchanged, secrets such as `.env.dev` and `.env.release` stay out of the repository, and each destructive write or publication waits for the user's confirmation.

```sh
git push --force
^ error: publication with no confirmation
```
