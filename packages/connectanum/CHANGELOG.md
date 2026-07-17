## 3.0.0-beta

- Start the coordinated 3.0 beta series for every Connectanum package.
- Preserve the legacy `connectanum` import surface as a compatibility facade
  over the modular client package.

## 2.2.8

- Add the `connectanum` compatibility facade package for existing consumers.
- Re-export the public `connectanum_client` WAMP client entrypoints without
  duplicating implementation code.
