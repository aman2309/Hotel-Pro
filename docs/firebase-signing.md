# Firebase Android signing fingerprints

Project: `yankees-hotel-pro`

Android application: `com.hotelpro1.app`

Firebase app ID: `1:731313332286:android:b27b800afa2dc084d4716f`

Current debug SHA-1: `19:AF:D0:BA:C7:73:AD:17:E5:15:BB:C7:17:EA:17:09:C2:FD:7A:06`

Current debug SHA-256: `DF:B1:D6:B5:DD:CC:C0:D4:13:AF:8D:04:14:C0:EF:D2:D0:65:C0:17:86:D3:68:D5:43:DB:92:07:55:E6:85:15`

Both debug and release variants currently use the debug keystore. The signing report was verified; certificate-registration requests failed because the connected Firebase account lacks project access. These hashes have not been confirmed as registered. A Play-distributed release also needs the actual Play App Signing certificate fingerprints.

After connecting an authorized Firebase account:

```sh
firebase apps:android:sha:create '1:731313332286:android:b27b800afa2dc084d4716f' '19:AF:D0:BA:C7:73:AD:17:E5:15:BB:C7:17:EA:17:09:C2:FD:7A:06' --project yankees-hotel-pro
firebase apps:android:sha:create '1:731313332286:android:b27b800afa2dc084d4716f' 'DF:B1:D6:B5:DD:CC:C0:D4:13:AF:8D:04:14:C0:EF:D2:D0:65:C0:17:86:D3:68:D5:43:DB:92:07:55:E6:85:15' --project yankees-hotel-pro
```
