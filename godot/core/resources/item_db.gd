class_name ItemDB
extends RefCounted
## كتالوج العناصر: الاسم، قيمة البيع عند المشتري، وهل هي «ساخنة» (تُصادر عند الاعتقال).

const ITEMS := {
	"document": {"name": "مستند سوق سوداء", "value": 0, "hot": false},
	"decoder": {"name": "جهاز فك تشفير", "value": 0, "hot": false},
	"decoder_epic": {"name": "جهاز فك تشفير نادر", "value": 0, "hot": false},
	"master_key": {"name": "مفتاح رئيسي", "value": 0, "hot": false},
	"eviction_right": {"name": "حق طرد", "value": 0, "hot": false},
	"pass_vip": {"name": "تصريح خاص", "value": 0, "hot": false},
	"drill": {"name": "مثقاب", "value": 0, "hot": false},
	"lockpick": {"name": "عُدّة أقفال", "value": 0, "hot": false},
	"deposit_key": {"name": "مفتاح صندوق ودائع", "value": 0, "hot": true},
	"jewelry": {"name": "مجوهرات", "value": 1800, "hot": true},
	"electronics": {"name": "إلكترونيات", "value": 900, "hot": true},
	"gold_bar": {"name": "سبيكة ذهب", "value": 12000, "hot": true},
	"art": {"name": "لوحة فنية", "value": 25000, "hot": true},
	"cash_bundle": {"name": "رزمة نقود", "value": 2500, "hot": true},
	"cargo": {"name": "شحنة مغلقة", "value": 6000, "hot": true},
	"title_plot_1": {"name": "سند أرض مستوى 1", "value": 0, "hot": false},
	"title_plot_2": {"name": "سند أرض مستوى 2", "value": 0, "hot": false},
	"title_plot_3": {"name": "سند أرض مستوى 3", "value": 0, "hot": false},
}


static func item_name(id: String) -> String:
	return ITEMS.get(id, {}).get("name", id)


static func value(id: String) -> int:
	return int(ITEMS.get(id, {}).get("value", 0))


static func is_hot(id: String) -> bool:
	return bool(ITEMS.get(id, {}).get("hot", false))
