# دمار — نسخة Unity (للوصول إلى جودة ستيم)

هذا المجلد يحتوي على **كود اللعبة الكامل بلغة C#** لمحرك Unity، بنفس منطق نسخة المتصفح:
السرقة، النجوم، مطاردة الشرطة (سيارات + شرطي راجل)، القيادة بفيزياء حقيقية، المخبأ، الاعتقال، والواجهة.

> **ملاحظة صريحة:** الكود مُتحقَّق من أنه يُترجَم (compile) بلا أخطاء، لكني لم أستطع تشغيله داخل محرر Unity
> من هنا. المشهد نفسه (المدينة، النماذج، الإضاءة) تبنيه أنت في المحرر باتباع الخطوات أدناه.
> إذا ظهر أي خطأ في Unity انسخه وأرسله لي وسأصلحه.

## لماذا Unity؟

- لغة C# أسهل بكثير من C++ في Unreal للبدء
- يعمل جيداً على أجهزة متوسطة، ويُصدِّر لويندوز مباشرة للنشر على ستيم
- قالب **HDRP** يعطي رسوماً واقعية (إضاءة فيزيائية، انعكاسات، ضباب حجمي، أسفلت مبلل)

---

## 1) التثبيت

1. نزّل **Unity Hub** من unity.com ثم ثبّت **Unity 6 LTS**.
2. أنشئ مشروعاً جديداً بقالب **High Definition 3D (HDRP)**.
   (إذا كان جهازك متوسطاً اختر **Universal 3D (URP)**: أخف، ورسومه جيدة.)
3. من **Window → Package Manager** ثبّت:
   - **AI Navigation** (لملاحة الشرطة)
   - **ProBuilder** (لبناء الشوارع والمباني بسرعة)
   - **TextMeshPro** (عادة موجود مسبقاً)
4. للنصوص العربية ثبّت **RTLTMPro** (مجاني ومفتوح المصدر):
   Package Manager → **+** → *Add package from git URL* → `https://github.com/pnarimani/RTLTMPro.git`
5. **Edit → Project Settings → Player → Active Input Handling = Both**
   (الكود يستخدم نظام الإدخال الكلاسيكي `Input.GetAxis`).
6. انسخ مجلد `Scripts` هذا إلى `Assets/Scripts` داخل مشروعك.

## 2) الأصول الواقعية (مجانية)

| ما تحتاجه | من أين |
|---|---|
| شخصيات بشرية واقعية + حركات (وقوف، مشي، ركض، لكم) | **Mixamo** (مجاني بحساب Adobe). اختر شخصيتين (لص وشرطي) ونزّل الحركات بخيار *In Place*. عند الاستيراد: Rig → **Humanoid** |
| سيارات | **Unity Asset Store** — فلتر *Free* وابحث عن "car" أو "police car" |
| مبانٍ ومدينة | Asset Store (حزم مدن مجانية) أو ابنِها بـ ProBuilder |
| خامات (أسفلت، طوب، خرسانة) وسماء HDRI ليلية | **Poly Haven** (CC0، مجانية تماماً) |
| أصوات (صفارة، محرك، إنذار) | freesound.org (تحقق من رخصة كل صوت) |

## 3) بناء المشهد خطوة بخطوة

### الطبقات (Layers)
أنشئ: `Buildings`، `Vehicles`، `Ground`. ضع المباني في `Buildings` والطرق في `Ground`.

### كائن GameManager
كائن فارغ عليه: **GameManager** + **WantedSystem** + **PoliceSpawner**.
- اربط `player` و `safehouseSpawn` (كائن فارغ أمام المخبأ).

### اللاعب
1. كائن `Player` عليه **CharacterController** (الارتفاع 1.8، نصف القطر 0.35) + **PlayerController**.
2. ضع نموذج Mixamo ابناً له واربطه في `visual`، واربط الـ **Animator** في `animator`.
3. `vehicleMask` = طبقة `Vehicles`.

### Animator Controller (للص والشرطي)
- معاملات: `Speed` (Float)، `Robbing` (Bool) للص، `Arresting` (Bool) للشرطي.
- **Blend Tree** على `Speed`: 0 → Idle، 2.5 → Walk، 8 → Run.
- من أي حالة إلى **Punch** عندما `Robbing` (أو `Arresting`) = true، والعودة عندما = false.

### الكاميرا
Main Camera عليها **ThirdPersonCamera**، اربط `player`، و `obstacleMask` = `Buildings`.

### السيارة (Prefab)
1. نموذج السيارة + **Rigidbody** (Mass = 1400، Interpolate = Interpolate).
2. أربعة كائنات فارغة عند العجلات عليها **WheelCollider** (Radius حسب العجلة، Suspension Distance = 0.2).
3. **VehicleController**: املأ `wheels` (collider + mesh)، فعّل `steer` للأماميتين و `motor` للخلفيتين.
4. طبقة السيارة كلها = `Vehicles`.
5. للسيارات المدنية أضف **TrafficAI** واملأ `route` بنقاط على مسار اليمين في الشوارع.

### سيارة الشرطة (Prefab)
انسخ Prefab السيارة وأضف:
- **PoliceCarAI**: `sightBlockers` = `Buildings`، `officerPrefab` = Prefab الشرطي.
- **SirenLights**: ضوءان (Point Light) أحمر وأزرق فوق السقف + AudioSource للصفارة (Loop)، واربط `police`.
- اسحب الـ Prefab إلى `policeCarPrefab` في **PoliceSpawner**.

### الشرطي الراجل (Prefab)
نموذج Mixamo للشرطي + **NavMeshAgent** (Speed 6.9) + **PoliceOfficerAI** + Animator.

### الملاحة (NavMesh)
1. **Window → AI → Navigation → Areas**: أضف منطقة اسمها **`Road`**.
2. على الطرق أضف **NavMeshModifier** واجعل Area = `Road`، والأرصفة والأزقة تبقى `Walkable`.
3. كائن فارغ عليه **NavMeshSurface** → اضغط **Bake**.

> هكذا تبقى سيارات الشرطة على الطرق، بينما الشرطي الراجل والأزقة الضيقة خاصة بالمشاة.

### المتاجر والمخبأ
- كائن فارغ أمام باب كل متجر عليه **Store**: اختر `kind` ثم كليك يمين على المكوّن → **تطبيق إعدادات النوع**.
  اربط `openVisuals` (اللافتة المضيئة) و `alarm` (صوت الإنذار).
- كائن أمام المخبأ عليه **Safehouse**.

### الواجهة (Canvas)
Canvas عليه **HUD**. استخدم **RTLTextMeshPro** للنصوص و **Image (Filled)** للأشرطة، واربط الحقول.
للخريطة المصغّرة: كاميرا ثانية عليها **MinimapCamera** (Orthographic، Size ≈ 120) تُخرج إلى Render Texture
تعرضها في **RawImage** دائري (بـ Mask).

### إضاءة ليلية واقعية (HDRP)
- Volume عالمي: **HDRI Sky** ليلية من Poly Haven بإضاءة منخفضة، **Fog** مع Volumetric، **Bloom**، **Screen Space Reflections**.
- مواد الأسفلت: Smoothness أعلى (0.6–0.8) لمظهر مبلل يعكس الأضواء.
- أعمدة الإنارة: Spot Light دافئ (≈3000K) بظلال فقط للقريبة منها.

## 4) قائمة اختبار

- [ ] المشي والركض واللياقة تعمل، والكاميرا لا تخترق الجدران
- [ ] F يركب السيارة وينزل منها، والقيادة والانجراف بـ Space يعملان
- [ ] E مطولاً عند المتجر يرفع النجوم ويضيف المال
- [ ] سيارات الشرطة تظهر بعيداً وتطاردك على الطرق، والشرطي ينزل إذا كنت ماشياً
- [ ] الاختباء يُنقص النجوم، والاعتقال يُصادر المال ويعيدك للمخبأ
- [ ] الإيداع في المخبأ يُحفظ بعد إعادة التشغيل

## 5) النشر على ستيم

1. سجّل في **Steamworks** (partner.steamgames.com) وادفع رسوم **Steam Direct** ($100 لكل لعبة).
2. جهّز صفحة المتجر: صور الغلاف (Capsules)، لقطات شاشة، فيديو، ووصف.
3. لبناء النسخة: **File → Build Profiles → Windows** ثم ارفعها بأداة **SteamPipe**.
4. للإنجازات وقوائم المتصدرين استخدم مكتبة **Steamworks.NET** (مجانية).

## 6) لاحقاً: اللعب الجماعي (شرطة ضد لصوص)

مثل Rob Run يحتاج خادماً يتحكم بالحالة: استخدم **Netcode for GameObjects** (من Unity) أو **Mirror** / **FishNet** (مجانية).
الكود الحالي مقسَّم بحيث يمكن نقل `WantedSystem` و `GameManager` إلى الخادم لاحقاً.

## بنية الكود

```
Scripts/
  Core/      GameManager (المال، الحفظ، الاعتقال) · WantedSystem (النجوم) · Compat
  Player/    PlayerController (المشي، الركض، ركوب السيارات) · ThirdPersonCamera
  Vehicles/  VehicleController (فيزياء WheelCollider) · DriveHelper · TrafficAI · SirenLights
  Police/    PoliceCarAI · PoliceOfficerAI · PoliceSpawner
  World/     Store (السرقة) · Safehouse (المخبأ)
  UI/        HUD · MinimapCamera
```
