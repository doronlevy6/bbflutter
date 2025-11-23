---
description: Workflow for deploying the Baller app to Android and Web
---

# נוהל עבודה - פיתוח ופריסה (Deployment)

מסמך זה מתאר את תהליך העבודה המומלץ לפיתוח ופריסה של אפליקציית Baller, תוך שימוש בבסיס קוד אחד (`BB_flutter`) עבור אנדרואיד ו-Web.

## 1. פיתוח שוטף
עבוד תמיד בתיקייה `BB_flutter`.
- **הרצה באנדרואיד**: `flutter run` (כרגיל).
- **הרצה ב-Web (מקומי)**: `flutter run -d chrome`.
  - הקוד עודכן כך שיזהה אוטומטית סביבת Web וישתמש בכתובת השרת של Production (`renderbbserver`), כך שאין צורך ב-`.env` ב-Web.

## 2. פריסה לאנדרואיד (Google Play)
תהליך זה נשאר ללא שינוי:
1. וודא שעדכנת את הגרסה ב-`pubspec.yaml`.
2. הרץ את הפקודה:
   ```bash
   flutter build appbundle --release
   ```
3. הקובץ יווצר ב-`build/app/outputs/bundle/release/app-release.aab`.
4. העלה את הקובץ ל-Google Play Console.

## 3. פריסה ל-Web (GitHub Pages)
במקום להעתיק קבצים ידנית ולתחזק פרויקט נפרד, השתמש בסקריפט האוטומטי שיצרנו.

1. וודא שאתה בתיקייה הראשית של `BB_flutter`.
2. הרץ את הסקריפט:
   ```bash
   ./deploy_web.sh
   ```
   *הסקריפט יבצע:*
   - בנייה של גרסת ה-Web (`flutter build web --release`).
   - ניקוי תיקיית היעד (`../BB_web`).
   - העתקת הקבצים החדשים לתיקיית היעד.

3. כנס לתיקיית ה-Web ודחוף לגיט:
   ```bash
   cd ../BB_web
   git add .
   git commit -m "Update web version"
   git push
   ```

## הערות חשובות
- **Environment Variables**: הקובץ `lib/managers/environment_manager.dart` עודכן כך שבסביבת Web הוא מתעלם מקובץ ה-`.env` ומשתמש ישירות בכתובת השרת הקבועה. זה פותר את הבעיות שהיו בטעינת משתני סביבה ב-Web.
- **בטיחות**: הסקריפט `deploy_web.sh` מוחק את תוכן תיקיית היעד (למעט `.git` ו-`README.md`) לפני העתקת הקבצים החדשים, כדי להבטיח שהגרסה נקייה ומעודכנת.
