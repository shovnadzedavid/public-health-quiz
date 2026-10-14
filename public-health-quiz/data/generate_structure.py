import json
from pathlib import Path

# სექციები, რომლებიც შენს საიტზეა წარმოდგენილი
sections = [
    "პრევენცია და ჯანმრთელობის განათლება",
    "ეპიდემიოლოგია",
    "ჯანდაცვის მენეჯმენტი",
    "გარემო და ინფექციების კონტროლი",
    "მტკიცებულებები და ჯანდაცვის პოლიტიკა"
]

# პაკეტების სტრუქტურა თითოეული სექციისთვის:
# 15 პაკეტი - 15 კითხვანი
# 15 პაკეტი - 20 კითხვიანი
# 8 პაკეტი - 25 კითხვიანი
# 7 პაკეტი - 30 კითხვიანი
package_distribution = [
    {"count": 15, "questions_per_package": 15},
    {"count": 15, "questions_per_package": 20},
    {"count": 8, "questions_per_package": 25},
    {"count": 7, "questions_per_package": 30}
]

# სტრუქტურის გენერაცია
quiz_structure = {}

for section in sections:
    quiz_structure[section] = []
    package_id = 1
    
    for group in package_distribution:
        for _ in range(group["count"]):
            quiz_structure[section].append({
                "package_number": package_id,
                "questions_count": group["questions_per_package"],
                "questions": []  # აქ ჩაიყრება მომავალში კითხვები
            })
            package_id += 1

# შედეგის შენახვა სტრუქტურის ფაილად
Path("quiz_structure.json").write_text(json.dumps(quiz_structure, ensure_ascii=False, indent=2) + "\n")

print("სტრუქტურა წარმატებით შეიქმნა! სულ არის", len(sections), "სექცია. თითოეულში არის", sum(g["count"] for g in package_distribution), "პაკეტი.")