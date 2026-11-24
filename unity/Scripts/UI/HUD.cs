using TMPro;
using UnityEngine;
using UnityEngine.UI;

namespace Damar
{
    /// <summary>
    /// واجهة اللعب. النصوص العربية تحتاج حزمة RTLTMPro (مجانية) — اسحب مكوّنات
    /// RTLTextMeshPro إلى الحقول أدناه مباشرة (هي من نوع TMP_Text).
    /// الصور (Image) يجب أن تكون Image Type = Filled لأشرطة التقدم.
    /// </summary>
    public class HUD : MonoBehaviour
    {
        [Header("المال")]
        public TMP_Text cashText;
        public TMP_Text bankText;
        public Image goalFill;

        [Header("النجوم")]
        public Image[] stars = new Image[5];
        public Color starOn = new Color(1f, 0.81f, 0.23f), starOff = new Color(1f, 1f, 1f, 0.16f);
        public TMP_Text wantedText;
        public GameObject loseBarRoot;
        public Image loseFill;

        [Header("التفاعل")]
        public TMP_Text hintText;
        public GameObject progressRoot;
        public TMP_Text progressLabel;
        public Image progressFill;
        public GameObject arrestRoot;
        public Image arrestFill;

        [Header("السيارة / اللياقة")]
        public GameObject speedoRoot;
        public TMP_Text speedText;
        public GameObject staminaRoot;
        public Image staminaFill;

        [Header("الرسائل")]
        public TMP_Text toastText;
        public float toastDuration = 2.6f;
        public GameObject bustedPanel;
        public TMP_Text bustedText;
        public GameObject winPanel;

        Store[] stores;
        Safehouse safehouse;
        float toastTimer;

        void OnEnable()
        {
            Store.Robbed += OnRobbed;
            Safehouse.Stashed += OnStashed;
            Safehouse.StashRefused += OnStashRefused;
        }

        void OnDisable()
        {
            Store.Robbed -= OnRobbed;
            Safehouse.Stashed -= OnStashed;
            Safehouse.StashRefused -= OnStashRefused;
            if (GameManager.I != null) { GameManager.I.Busted -= OnBusted; GameManager.I.Won -= OnWon; }
            if (WantedSystem.I != null) WantedSystem.I.LevelChanged -= OnWantedChanged;
        }

        void Start()
        {
#if UNITY_2023_1_OR_NEWER
            stores = FindObjectsByType<Store>(FindObjectsSortMode.None);
            safehouse = FindFirstObjectByType<Safehouse>();
#else
            stores = FindObjectsOfType<Store>();
            safehouse = FindObjectOfType<Safehouse>();
#endif
            GameManager.I.Busted += OnBusted;
            GameManager.I.Won += OnWon;
            WantedSystem.I.LevelChanged += OnWantedChanged;
            if (bustedPanel) bustedPanel.SetActive(false);
            if (winPanel) winPanel.SetActive(false);
        }

        static string Money(int v) => "$" + v.ToString("N0");

        public void Toast(string msg, Color color)
        {
            if (!toastText) return;
            toastText.text = msg;
            toastText.color = color;
            toastText.gameObject.SetActive(true);
            toastTimer = toastDuration;
        }

        void OnRobbed(Store s, int amount) => Toast($"+{Money(amount)}  اهرب إلى المخبأ!", new Color(0.5f, 1f, 0.62f));
        void OnStashed(int amount) => Toast($"تم إخفاء {Money(amount)}", new Color(0.5f, 1f, 0.62f));
        void OnStashRefused() => Toast("الشرطة تلاحقك! تخلّص منها أولاً", new Color(1f, 0.42f, 0.42f));
        void OnWon() { if (winPanel) winPanel.SetActive(true); }

        void OnWantedChanged(int level)
        {
            if (level == 0) Toast("تخلّصت من الشرطة!", new Color(0.56f, 0.83f, 1f));
        }

        void OnBusted(int lost)
        {
            if (!bustedPanel) return;
            bustedPanel.SetActive(true);
            if (bustedText) bustedText.text = lost > 0 ? $"صادرت الشرطة {Money(lost)}. مالك في المخبأ بأمان." : "لم يكن معك مال هذه المرة.";
        }

        /// <summary>اربطه بزر «العودة» في لوحة الاعتقال أو الفوز.</summary>
        public void ClosePanels()
        {
            if (bustedPanel) bustedPanel.SetActive(false);
            if (winPanel) winPanel.SetActive(false);
        }

        void Update()
        {
            var gm = GameManager.I;
            var ws = WantedSystem.I;
            var player = gm.player;

            if (cashText) cashText.text = Money(gm.Cash);
            if (bankText) bankText.text = Money(gm.Bank);
            if (goalFill) goalFill.fillAmount = Mathf.Clamp01((float)gm.Bank / gm.goal);

            bool blink = ws.IsHidden && Mathf.Repeat(Time.time, 0.6f) < 0.3f;
            for (int i = 0; i < stars.Length; i++)
                if (stars[i]) stars[i].color = i < ws.Level && !blink ? starOn : starOff;
            if (wantedText) wantedText.text = ws.Level == 0 ? "" : ws.IsHidden ? "اختفيت عن أنظارهم… ابقَ مختبئاً" : "الشرطة تراك! اهرب واختبئ";
            if (loseBarRoot) loseBarRoot.SetActive(ws.IsHidden);
            if (loseFill) loseFill.fillAmount = ws.LoseProgress;

            if (arrestRoot) arrestRoot.SetActive(gm.ArrestProgress > 0.01f);
            if (arrestFill) arrestFill.fillAmount = gm.ArrestProgress;

            if (speedoRoot) speedoRoot.SetActive(!player.OnFoot);
            if (speedText && !player.OnFoot) speedText.text = Mathf.RoundToInt(player.CurrentVehicle.SpeedKmh).ToString();
            if (staminaRoot) staminaRoot.SetActive(player.OnFoot);
            if (staminaFill) staminaFill.fillAmount = player.Stamina;

            // التلميحات وشريط السرقة
            string hint = "";
            Store robbing = null;
            foreach (var s in stores)
            {
                if (s.IsBeingRobbed) robbing = s;
                if (!s.PlayerInRange) continue;
                hint = s.IsOpen
                    ? $"اضغط مطولاً E لسرقة {s.displayName}  ({Money(s.valueRange.x)} – {Money(s.valueRange.y)})"
                    : $"{s.displayName} مغلق — عُد بعد {Mathf.CeilToInt(s.CooldownLeft)} ثانية";
            }
            if (safehouse && safehouse.PlayerInRange)
                hint = gm.Cash > 0 ? $"اضغط E لإخفاء {Money(gm.Cash)} في المخبأ" : "المخبأ — أحضر المال المسروق هنا";
            if (hint == "" && player.OnFoot)
            {
                var v = player.FindNearestVehicle();
                if (v) hint = v.isPolice ? "اضغط F لسرقة سيارة الشرطة (+2 نجمة)" : "اضغط F لركوب السيارة";
            }
            if (hintText) hintText.text = hint;

            if (progressRoot) progressRoot.SetActive(robbing != null);
            if (robbing != null)
            {
                if (progressLabel) progressLabel.text = $"جارٍ سرقة {robbing.displayName}…";
                if (progressFill) progressFill.fillAmount = robbing.Progress;
            }

            if (toastTimer > 0f)
            {
                toastTimer -= Time.deltaTime;
                if (toastTimer <= 0f && toastText) toastText.gameObject.SetActive(false);
            }
        }
    }
}
