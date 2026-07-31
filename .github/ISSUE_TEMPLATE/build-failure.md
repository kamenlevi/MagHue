---
name: Build failure
about: make install didn't produce MagHue.app
title: "Build fails on macOS <version>"
labels: build
---

You don't need the whole build log — the last part is what matters. Run:

```sh
make install > /tmp/maghue-build.log 2>&1
tail -40 /tmp/maghue-build.log
```

and paste that below. (You can also drag `/tmp/maghue-build.log` straight into
this box to attach the whole thing.)

```
paste here
```

**Your setup**

- macOS version (`sw_vers -productVersion`):
- Mac model:
- Swift version (`swift --version`):
