# T4n OS Repository (`repo-t4nos`)

Signed XBPS binary packages that are **not in the official Void Linux
repositories**. Works on T4n OS and plain Void Linux, for **glibc and musl**.
One repository, nine release tags (`x86_64`, `x86_64-musl`, `aarch64`,
`aarch64-musl`, `armv6l`, `armv6l-musl`, `armv7l`, `armv7l-musl`, `i686`).

- Package search: https://repo-web.t4nlabs.web.id/
- XBPS endpoint: `https://repo.t4nlabs.web.id/<tag>`

## Quick install

```sh
curl -fsSLO https://repo.t4nlabs.web.id/setup.sh
less setup.sh
sudo sh setup.sh
```

## Key fingerprint

```
63:35:0c:65:0d:a5:f1:87:52:7e:c5:e9:13:3a:d6:2a
```

Signed by `T4n Labs`; one key signs every tag. Answer `yes` to the XBPS key prompt
only if the fingerprint it shows matches this one exactly.

## Documentation

| | English | Bahasa Indonesia |
|---|---|---|
| Users | [vdocs/EN/USER.md](vdocs/EN/USER.md) | [vdocs/ID/USER.md](vdocs/ID/USER.md) |
| Developers & maintainers | [vdocs/EN/DEV.md](vdocs/EN/DEV.md) | [vdocs/ID/DEV.md](vdocs/ID/DEV.md) |

## Contributing

Contributions (templates, tools, docs) go through **fork + Pull Request**. Only
the Founder has write access and holds the signing key; binaries are built,
signed and indexed by CI. See the developer guide above.

## License

Not decided yet.

---

**[T4n Labs](https://t4nlabs.web.id/)** ◉ **[Gh0sT4n](https://gh0st4n.my.id/)**