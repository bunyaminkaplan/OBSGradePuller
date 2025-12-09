import requests
from bs4 import BeautifulSoup
import shutil
import os
import sys
import re
from rich.console import Console
from rich.table import Table
from rich.progress import Progress, SpinnerColumn, TextColumn

# --- 1. AYARLAR & SABİTLER ---
LOGIN_URL = "https://obs.ozal.edu.tr/oibs/std/login.aspx"
GRADES_URL = "https://obs.ozal.edu.tr/oibs/std/not_listesi_op.aspx"
STATS_URL = "https://obs.ozal.edu.tr/oibs/acd/new_not_giris_istatistik.aspx"

# Kullanıcı Bilgileri
USER_NO = "02240202048"
SIFRE = "SIFRE" 

console = Console()
session = requests.Session()
session.headers.update({
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Referer": "https://obs.ozal.edu.tr/oibs/std/login.aspx",
    "Origin": "https://obs.ozal.edu.tr",
    "Cache-Control": "no-cache"
})

# --- 2. YARDIMCI FONKSİYONLAR ---

def get_hidden_inputs(soup):
    data = {}
    for inp in soup.find_all("input", type="hidden"):
        if inp.get("name"):
            data[inp.get("name")] = inp.get("value", "")
    return data

def solve_captcha(soup):
    img_tag = soup.find(id="imgCaptchaImg")
    if not img_tag: return ""
    
    captcha_src = img_tag.get("src")
    base_url = "https://obs.ozal.edu.tr/oibs/std/"
    
    if not captcha_src.startswith("http"):
        captcha_url = base_url + captcha_src.lstrip("/")
    else:
        captcha_url = captcha_src

    r = session.get(captcha_url, stream=True)
    if r.status_code == 200:
        with open("temp_captcha.png", "wb") as f:
            r.raw.decode_content = True
            shutil.copyfileobj(r.raw, f)
        
        if sys.platform == "win32": os.startfile("temp_captcha.png")
        elif sys.platform == "darwin": os.system("open temp_captcha.png")
        else: os.system("xdg-open temp_captcha.png")
        
        return console.input("[bold yellow]Resimdeki kodu gir: [/bold yellow]")
    return ""

def parse_raw_grades(raw_text):
    """ 'Vize : 80 Final : --' şeklindeki stringi parse eder."""
    grades = {"Vize": "-", "Final": "-", "Büt": "-"}
    
    vize_match = re.search(r"Vize\s*:\s*([\d\w-]+)", raw_text)
    if vize_match: grades["Vize"] = vize_match.group(1)
    
    final_match = re.search(r"Final\s*:\s*([\d\w-]+)", raw_text)
    if final_match: grades["Final"] = final_match.group(1)
    
    but_match = re.search(r"Bütünleme\s*:\s*([\d\w-]+)", raw_text)
    if but_match: grades["Büt"] = but_match.group(1)
    
    return grades

def extract_all_averages(html_content):
    """
    HTML'i satır satır okur ve Vize/Final/Büt ortalamalarını ayıklar.
    State Machine mantığı kullanılır.
    """
    averages = {"Vize": "?", "Final": "?", "Büt": "?"}
    soup = BeautifulSoup(html_content, "html.parser")
    table = soup.find("table", id="grdIstSnv")
    
    if not table: return averages

    rows = table.find_all("tr")
    current_context = None # Hangi sınav bölgesindeyiz?

    for row in rows:
        text = row.get_text(strip=True)
        
        # 1. Bölge Tespiti (Header Satırları)
        if "Ara Sınav" in text:
            current_context = "Vize"
        elif "Yarıyıl Sonu" in text or "Final" in text:
            current_context = "Final"
        elif "Bütünleme" in text:
            current_context = "Büt"
        
        # 2. Veri Yakalama (Ortalama Satırı)
        # "not ortalaması" ifadesini arıyoruz
        if "not ortalaması" in text and current_context:
            cols = row.find_all("td")
            if len(cols) > 1:
                val = cols[1].get_text(strip=True)
                averages[current_context] = val

    return averages

# --- 3. ANA AKIŞ ---

def main():
    console.clear()
    console.rule("[bold cyan]🎓 OBS Grade Puller v3.0 (Pro Edition)[/bold cyan]")

    # --- LOGIN ---
    with console.status("[bold green]OBS'ye Bağlanılıyor...", spinner="dots"):
        r_get = session.get(LOGIN_URL)
        soup = BeautifulSoup(r_get.content, "html.parser")
        payload = get_hidden_inputs(soup)
    
    captcha_code = solve_captcha(soup)

    with console.status("[bold green]Giriş Yapılıyor...", spinner="earth"):
        payload.update({
            "txtParamT01": USER_NO, "txtParamT02": SIFRE, "txtParamT1": SIFRE,
            "txtSecCode": captcha_code, "__EVENTTARGET": "btnLogin", 
            "__EVENTARGUMENT": "", "txt_scrWidth": "1920", "txt_scrHeight": "1080"
        })
        if "btnLogin" in payload: del payload["btnLogin"]
        
        r_post = session.post(LOGIN_URL, data=payload)
        
        if "login.aspx" in r_post.url:
            console.print("[bold red]❌ Giriş Başarısız! Şifre veya Captcha hatalı.[/bold red]")
            return
        
        console.print("[bold green]✅ Giriş Başarılı![/bold green]")

    # --- NOT LİSTESİ ---
    session.headers.update({"Referer": GRADES_URL})
    r_grades = session.get(GRADES_URL)
    soup_grades = BeautifulSoup(r_grades.content, "html.parser")
    
    table = soup_grades.find(id="grd_not_listesi")
    if not table:
        console.print("[red]Not tablosu bulunamadı![/red]")
        return
    
    rows = table.find_all("tr")[1:]
    
    # Dönem
    donem_select = soup_grades.find("select", id="cmbDonemler")
    selected_donem = "20251"
    if donem_select:
        opt = donem_select.find("option", selected=True)
        if opt: selected_donem = opt.get("value")

    # --- GÜÇLENDİRİLMİŞ TABLO YAPISI ---
    output_table = Table(title=f"Not Durumu ({selected_donem})", show_lines=True)
    output_table.add_column("Ders", style="cyan", no_wrap=True)
    
    # Her sınav türü için ayrı sütun grubu
    output_table.add_column("Vize", justify="center")
    output_table.add_column("Ort.", justify="center", style="dim")
    
    output_table.add_column("Final", justify="center")
    output_table.add_column("Ort.", justify="center", style="dim")
    
    output_table.add_column("Büt", justify="center")
    output_table.add_column("Ort.", justify="center", style="dim")
    
    output_table.add_column("Harf", justify="center", style="bold magenta")

    # --- ANALİZ DÖNGÜSÜ ---
    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        transient=True
    ) as progress:
        task = progress.add_task("[green]Dersler analiz ediliyor...", total=len(rows))

        for row in rows:
            cols = row.find_all("td")
            if len(cols) < 5: continue
            
            ders_adi = cols[2].get_text(strip=True)
            harf_notu = cols[6].get_text(strip=True)
            raw_notlar = cols[4].get_text(" ", strip=True)
            
            # Senin notların
            my_grades = parse_raw_grades(raw_notlar)
            
            progress.update(task, description=f"[yellow]Veri çekiliyor: {ders_adi}")
            
            # Sınıf Ortalamaları (Varsayılan ?)
            class_avgs = {"Vize": "?", "Final": "?", "Büt": "?"}
            
            # İstatistik Butonu Var mı?
            stats_btn = row.find("a", id=re.compile(r"btnIstatistik"))
            if stats_btn:
                href = stats_btn.get("href", "")
                match = re.search(r"__doPostBack\('([^']*)'", href)
                if match:
                    target = match.group(1)
                    
                    # 1. AJAX Trigger (Context Switch)
                    hidden_data = get_hidden_inputs(soup_grades)
                    hidden_data.update({
                        "ScriptManager1": f"UpdatePanel1|{target}",
                        "__EVENTTARGET": target, "__EVENTARGUMENT": "", "__ASYNCPOST": "true",
                        "cmbDonemler": selected_donem
                    })
                    
                    session.headers.update({"X-MicrosoftAjax": "Delta=true"})
                    session.post(GRADES_URL, data=hidden_data)
                    
                    # 2. İstatistik Sayfasına Git
                    if "X-MicrosoftAjax" in session.headers: del session.headers["X-MicrosoftAjax"]
                    r_stats = session.get(STATS_URL)
                    
                    # 3. Tüm Ortalamaları Çek
                    class_avgs = extract_all_averages(r_stats.text)
            
            # Tabloya Ekle
            output_table.add_row(
                ders_adi,
                my_grades["Vize"], class_avgs["Vize"],
                my_grades["Final"], class_avgs["Final"],
                my_grades["Büt"], class_avgs["Büt"],
                harf_notu
            )
            progress.advance(task)

    console.print(output_table)
    
    if os.path.exists("temp_captcha.png"): os.remove("temp_captcha.png")
    if os.path.exists("debug_ajax_fail.html"): os.remove("debug_ajax_fail.html")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        console.print("\n[bold red]İşlem iptal edildi.[/bold red]")