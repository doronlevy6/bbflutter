# מדריך לפרויקט Baller

מסמך זה מרכז את כל המידע על מבנה הפרויקט, תהליכי העבודה והפריסה (Deployment).

## 📂 מבנה הפרויקט

הפרויקט מחולק לשלושה חלקים עיקריים הנמצאים בתיקיות נפרדות:

### 1. `BB_flutter` (הפרויקט הראשי)
*   **מה זה?**: קוד המקור של האפליקציה (כתוב ב-Flutter/Dart).
*   **שימוש**: כאן מתבצע כל הפיתוח - גם לאפליקציית המובייל וגם לאתר ה-Web.
*   **גיט**: `https://github.com/doronlevy6/bbflutter`
*   **קובץ חשוב**: `lib/managers/environment_manager.dart` - מנהל את הכתובות לשרת (Local vs Production).

### 2. `BB_web` (תוצר ה-Web)
*   **מה זה?**: התיקייה שמכילה את הקבצים המוכנים לאינטרנט (HTML, JS, CSS) שנוצרו מתוך `BB_flutter`.
*   **שימוש**: משמשת אך ורק להעלאת האתר ל-GitHub Pages. **אין לערוך כאן קוד ידנית!**
*   **גיט**: `https://github.com/doronlevy6/doronlevy6.github.io`
*   **כתובת האתר**: `https://doronlevy6.github.io/`

### 3. `BB_server` (השרת / Backend)
*   **מה זה?**: שרת Node.js/Express שמנהל את ה-DB והלוגיקה.
*   **שימוש**: רץ על שירות הענן Render.
*   **גיט**: `https://github.com/doronlevy6/renderBbServer`
*   **DB**: משתמש ב-PostgreSQL המאוחסן ב-Neon.tech.

---

## 🚀 נוהלי עבודה ופריסה (Deployment)

### 📱 1. עדכון אפליקציית אנדרואיד (Google Play)
1.  פתח את `BB_flutter`.
2.  עדכן את הגרסה בקובץ `pubspec.yaml` (למשל: `version: 1.0.21+21`).
3.  הרץ בטרמינל:
    ```bash
    flutter build appbundle --release
    ```
4.  הקובץ המוכן יחכה לך ב: `build/app/outputs/bundle/release/app-release.aab`.
5.  העלה את הקובץ ל-Google Play Console.

### 🌐 2. עדכון אתר האינטרנט (GitHub Pages)
1.  פתח את `BB_flutter`.
2.  הרץ את הסקריפט האוטומטי:
    ```bash
    ./deploy_web.sh
    ```
    *(הסקריפט בונה את האתר, מוחק את הישן ב-`BB_web` ומעתיק את החדש)*.
3.  עבור לתיקיית ה-Web:
    ```bash
    cd ../BB_web
    ```
4.  דחוף לגיט:
    ```bash
    git add .
    git commit -m "Update web site"
    git push
    ```
    *(הערה: וודא שאתה דוחף ל-`origin` הנכון שמצביע ל-`doronlevy6.github.io`)*.

### 🖥️ 3. עדכון השרת (Render)
1.  פתח את `BB_server`.
2.  בצע שינויים בקוד.
3.  דחוף לגיט:
    ```bash
    git add .
    git commit -m "Update server logic"
    git push
    ```
4.  **Render** מזהה אוטומטית את הדחיפה ל-`main` ומעדכן את השרת לבד.

---

## 🔑 ניהול משתני סביבה (Environment Variables)

### בשרת (`BB_server`)
*   **במחשב שלך (Local)**: יש קובץ `.env` שמכיל הגדרות ל-Localhost. קובץ זה **לא** עולה לגיט (הוא מסומן כ-`assume-unchanged` או ב-gitignore).
*   **בגיטהאב**: קיים קובץ `.env` עם הגדרות הפרודקשן (Neon DB), כדי שיהיה גיבוי לקונפיגורציה.
*   **ב-Render**: המשתנים מוגדרים ב-Dashboard תחת Environment Variables.

### באפליקציה (`BB_flutter`)
*   הקובץ `lib/managers/environment_manager.dart` אחראי לנתב את הבקשות:
    *   **במצב פיתוח**: פונה ל-Localhost.
    *   **במצב Web**: מזהה אוטומטית (`kIsWeb`) ופונה לכתובת הפרודקשן (`renderbbserver.onrender.com`).
    *   **במצב Production (אפליקציה)**: פונה לכתובת הפרודקשן.

---

## 🛠️ פקודות שימושיות

*   **הרצת האפליקציה (מובייל)**: `flutter run`
*   **הרצת האפליקציה (ווב מקומי)**: `flutter run -d chrome`
*   **הרצת השרת (מקומי)**: `npm run dev` (בתוך `BB_server`)
* הרצת קוסץ הווב ודחיפתו לגיטהאב: `./deploy_web.sh`
