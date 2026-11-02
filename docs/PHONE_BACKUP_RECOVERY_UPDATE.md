# फोन का verified backup और recovery स्थिति

11 अक्टूबर 2026। User की अनुमति से network-free same-package/signature backup APK अस्थायी update किया। Navigation bar से बटन छिपने पर SafeArea UI ठीक किया। कोई uninstall/data clear नहीं किया। Export के बाद original captured 1.0.6+13 APK वापस लगाने का परिणाम Success है। Airplane mode 1, Wi-Fi 0 हैं। Production data/rules/migration नहीं बदले।

## सुरक्षित evidence

Private folder: `/Users/raghuwansh/hotel_pro_1/.checkpoints/rollout-20261010/phone-recovery-1791696365/`.
Original export `Hotel_Pro_1_Full_Backup_1791696615363.json`, 260894 bytes.
SHA256 `be231a92d829ff5e33879dcece6b74abc1e6db064266b6da9e79cab55a9d067e` फोन स्क्रीन से exact मिला। Raw preference XML hash native source hash से exact मिला। Original file निजी permissions से सुरक्षित है। तुलना के लिए derived comparison-input.json अलग है; original export नहीं बदला।

## Local बनाम पिछली cloud audit

- Local में 12 room IDs मिले, duplicate/missing room IDs नहीं। सभी 12 canonical cloud IDs से मिलते हैं। 10 empty rooms के common fields मेल खाते हैं।
- Room 101: 11 अक्टूबर 10:32 की BOOKED state, advance 0। Room 102: 11 अक्टूबर 10:52 की BOOKED state, advance ₹500। पिछली cloud audit में वही rooms EMPTY थे। ये नई local bookings सुरक्षित हैं; अभी production पर upload नहीं की गईं। Times stored local wall-clock values हैं।
- Local में केवल एक guest CUST-0001 है। उसी ID का cloud guest soft-deleted है, लेकिन name/mobile/ID/address/history fields अलग हैं। इसे समान guest मानकर merge या revive करना सुरक्षित नहीं। ID reuse/collision की समीक्षा चाहिए; कारण अभी प्रमाणित नहीं। पुराने guest, उसके bills और Storage photos का संबंध कायम रखें। नई identity के लिए reviewed stable guest ID/alias और current-stay references तय करें।
- Local guest में front/back image strings हैं। Decode हुए recognized images की अलग private copies और hashes सुरक्षित किए हैं। इन्हें पुराने cloud CUST-0001 के ID photos से स्वचालित replace/link नहीं करना है। Manual person/card association बाकी है।
- Bills और expenses की preference keys नहीं मिलीं। इसे शून्य इतिहास का प्रमाण न मानें। Cloud के 3 पुराने bills और 9 payments सुरक्षित snapshots में रहें; 3 payment alias pairs का dedup review बाकी है। Local ₹500 advance को पुराने room-based payment ID पर overwrite या duplicate receipt के रूप में न जोड़ें; current-stay आधारित idempotent event चाहिए।
- Local trialStart `2026-10-01T10:41:52.381990` मिला और raw copy सुरक्षित है। यह इस फोन की stored date है; इससे किसी पहले install की earliest trial date सिद्ध नहीं होती। hp1_license_on और hp1_license_hash नहीं मिले। Activation को false घोषित या नई activation fabricate नहीं करेंगे; entitlement/पूर्व device evidence आवश्यक है। Cloud license भी पिछली audit में absent था।

## आगे का स्पष्ट प्रस्ताव

1. नई दो bookings को local source hash तथा room/date/time से stable current-stay IDs दें; cloud EMPTY room updates को precondition और current server snapshot से मिलाएँ। ₹500 का exactly-once advance event उसी stay से जुड़े। नया bill न बनाएँ।
2. पुराने cloud history तथा नए CUST-0001 identity collision को अलग रखें; approved alias map में new guest/stay/photo references लिखें। Old deleted records bulk revive न हों।
3. पुरानी activation का अतिरिक्त entitlement evidence लें; returning owner missing-license पर नए trial creation को रोकें। सुरक्षित की गई local date का approved license recovery में provenance रहे।
4. Latest read-only cloud comparison और owner-verified PHP export बाकी हैं। वर्तमान तुलना 10 अक्टूबर snapshot से है; इसे आज के live cloud की स्थिति न कहें।
5. इस manifest का पहले disposable local emulator dry-run, repeat-run dedup और photo/financial checks करें। Production migration/rules तथा real-number login से पहले final effects दिखाकर अलग user confirmation लें।

अभी स्थायी sync APK फोन पर नहीं लगाया है। Physical phone offline रखें; original app launch करके writer चालू करने की जरूरत नहीं। Cloud-only इतिहास restore, full two-device production sync, activation restoration और PHP comparison अभी बाकी हैं।

## PIN लगाने के बाद सत्यापित update

11 अक्टूबर 2026, लगभग 11:13 बजे नया offline export लिया। Private checkpoint `/Users/raghuwansh/hotel_pro_1/.checkpoints/rollout-20261010/phone-post-pin-1791697396/` में original JSON और summary सुरक्षित हैं। File 261456 bytes, SHA256 `82ff5e5e57deecc96791ce20e9180ef7bc489cd948438466571201e702ed08ff`; फोन file और Mac copy के hashes मिले। Raw preference XML hash भी मिला।

अब local hp1_license_on true, PIN hash present और embedded recognized allowlist से matching है। PIN/hash की actual value public report/chat में नहीं दिखाई गई। Local trial date पहले जैसी है। Room/guest data पिछले verified backup से exact समान है: 12 rooms, booked 101/102 और guest/photo copies कायम हैं। Earlier activation-missing स्थिति इस नए local backup के लिए resolved है; पुराने install की activation history इससे सिद्ध नहीं होती। Cloud license अभी create/update नहीं किया।

Approved recovery प्रस्ताव में इसी recognized local activation और सुरक्षित trial date को owner-verified cloud license में transaction/preconditions के साथ रखना शामिल हो सकता है। Guest ID collision, financial idempotency, current live snapshot और PHP comparison की बाकी शर्तें अभी लागू हैं। Production execution अलग confirmation से ही होगा।
