# Recovery dry-run: 11 अक्टूबर 2026

Production और physical phone में कोई बदलाव नहीं हुआ। Verified post-PIN backup और 10 अक्टूबर owner cloud snapshot की निजी copies से localhost Firebase Firestore/Storage emulator में अलग disposable business clones बनाए। असली guest details/photos केवल इस local private test में हैं। Mac के साधारण LOCAL TEST Android account की mapping/records नहीं बदले।

## Guest collision का प्रस्ताव

पुराने cloud CUST-0001, उसके deleted marker, bills, bookings और payments जस के तस रहे। वर्तमान room bookings के phone-based stable guest IDs अलग रखे। Local guest row तभी जोड़ी जब room का phone और ID number दोनों मिले; Mismatch मिलने पर room-only candidate review के लिए flag होता। इस backup में दोनों bookings का phone और ID number उसी local guest से मिला, इसलिए एक नया guest ID और दो अलग stay IDs बने। नया ID पुराने CUST-0001 पर overwrite नहीं हुआ। Local front/back photos matching नए guest की versioned paths पर गईं; पुराने guest से नहीं जोड़ीं। यह proposed mapping है, production में स्वीकार/लागू नहीं हुई।

## आठ automated checks पास

1. वही recovery transaction दूसरी बार: zero अतिरिक्त writes/events।
2. दो current bookings और केवल एक नया ₹500 advance; कोई नया bill नहीं।
3. सभी पुराने bills/payments/bookings/guests और deleted markers exact अपरिवर्तित।
4. Guest ID collision अलग; दोनों current bookings सही matching नए guest से जुड़ीं।
5. Fresh SDK client ने activation और trial timestamp पढ़ा; trial reset rules ने रोका।
6. दूसरे owner की room access rules ने रोकी।
7. Fresh SDK client से नई दोनों photos के downloaded SHA256 source bytes से मिले।
8. Recovery के बाद दूसरे बदलाव वाले room पर stale recovery conflict हुई; नया rent overwrite नहीं हुआ।

Test script `tools/firebase_tests/recovery.test.mjs` केवल explicit localhost और demo-hotel-pro-sync project इस्तेमाल करता है। यह production migration tool नहीं है। Public output में guest/ID/PIN details नहीं हैं। Private alias manifest/results post-PIN checkpoint में हैं। प्रत्येक script run नया disposable clone बनाता है; एक clone पर apply दो बार चलाकर idempotency जाँची गई।

## सीमाएँ और deployment से पहले शर्तें

ये Firebase SDK/rules dry-run tests हैं; Android ऐप की screen से पूरे वास्तविक recovery/reinstall flows पास होने का दावा नहीं। दो वास्तविक phones/OTP, Android native photo restore, offline native payment replay और actual migration integration अभी बाकी हैं। Script के stable stay/guest IDs ऐप के conventions पर आधारित हैं, लेकिन production adapter/approved aliases को ऐप के codec/journal में जोड़ना और Android integration जाँचना बाकी है। पुराने room-based booking IDs को revive नहीं किया।

Trial backup में timezone-less local string है। इस test में Asia/Kolkata +05:30 इस्तेमाल किया; original phone की timezone पुष्टि और original string provenance production manifest में चाहिए। पुराने install की earliest trial entitlement इस date से सिद्ध नहीं। Local recognized activation सही सुरक्षित है; production cloud license अभी absent audit स्थिति में है, इसे लिखा नहीं।

Photo test शुरू में गलत test path, फिर अलग project के cross-service Storage lookup से denied हुआ। App के वास्तविक versions/hash/id_front.jpg या id_back.jpg path और server के same demo project पर पूरा परीक्षण पास हुआ। Permissions ढीली नहीं की गईं। Trial-reset test का PERMISSION_DENIED अपेक्षित सफल सुरक्षा check है।

Latest live read-only owner snapshot, PHP-only export, deletion intent और room-only guest/card association की समीक्षा अभी चाहिए। उसके बाद per-record before/after hash और financial alias manifest, missing-license returning-owner guard तथा Android integration तैयार करें। Production rules/migration से पहले user को final प्रभाव दिखाकर अलग confirmation लें।
