import asyncio
import os
import platform
import subprocess
from typing import List, Callable
from dataclasses import dataclass

from playwright.async_api import async_playwright
from rich.console import Console
from rich.table import Table
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich.prompt import Prompt
from rich.panel import Panel

# --- 1. VERİ MODELİ ---
@dataclass
class StudentGrade:
    course_name: str
    midterm: str
    final: str
    letter_grade: str

# --- 2. ARAYÜZ KATMANI (UI) ---
class TerminalUI:
    def __init__(self):
        self.console = Console()

    def show_captcha(self, image_path: str) -> str:
        """Captcha resmini açar ve kullanıcıdan kodu ister."""
        self.console.print(f"[yellow]! Güvenlik doğrulaması gerekiyor. Resim açılıyor...[/yellow]")
        
        # İşletim sistemine göre resmi aç
        if platform.system() == "Windows":
            os.startfile(image_path)
        elif platform.system() == "Darwin":
            subprocess.call(("open", image_path))
        else:
            subprocess.call(("xdg-open", image_path))

        return Prompt.ask("[bold cyan]Resimdeki kodu girin[/bold cyan]")

    def display_grades(self, grades: List[StudentGrade]):
        """Notları tablo olarak basar."""
        if not grades:
            self.console.print("[red]Görüntülenecek not bulunamadı![/red]")
            return

        table = Table(title="🎓 Dönem Notları", border_style="blue", header_style="bold magenta")

        table.add_column("Ders Adı", style="cyan", no_wrap=True)
        table.add_column("Vize", justify="center")
        table.add_column("Final", justify="center")
        table.add_column("Harf", justify="center", style="bold")

        for grade in grades:
            # FF ise kırmızı, diğerleri yeşil
            color = "red" if grade.letter_grade in ["FF", "FD", "DZ"] else "green"
            formatted_grade = f"[{color}]{grade.letter_grade}[/{color}]"
            
            table.add_row(
                grade.course_name,
                grade.midterm,
                grade.final,
                formatted_grade
            )

        self.console.print(table)
        
    def show_error(self, message: str):
        self.console.print(Panel(message, title="Hata", style="bold red"))

# --- 3. SCRAPER SERVİSİ (Logic) ---
class UniversityScraper:
    def __init__(self, login_url: str):
        self.login_url = login_url

    async def fetch_grades(self, username, password, captcha_callback: Callable[[str], str]) -> List[StudentGrade]:
        async with async_playwright() as p:
            # Viewport ayarı ekledim ki sayfa geniş açılsın, elementler sıkışmasın
            browser = await p.chromium.launch(headless=True)
            context = await browser.new_context(viewport={"width": 1920, "height": 1080})
            page = await context.new_page()

            try:
                # 1. GİRİŞ İŞLEMLERİ
                await page.goto(self.login_url)
                
                await page.fill("#txtParamT01", username)
                await page.click("#txtParamT02", force=True)
                await page.evaluate("document.getElementById('txtParamT02').removeAttribute('readonly')")
                await page.fill("#txtParamT02", password)   

                if await page.locator("#imgCaptchaImg").count() > 0:
                    temp_img = "captcha.png"
                    await page.locator("#imgCaptchaImg").screenshot(path=temp_img)
                    code = captcha_callback(temp_img) 
                    await page.fill("#txtSecCode", code) 
                    if os.path.exists(temp_img): os.remove(temp_img)

                await page.click("#btnLogin") 
                await page.wait_for_load_state("networkidle")

                # 2. MENÜ TIKLAMA (Native Click)
                print("Menü linki DOM üzerinde aranıyor...")
                target_link = page.locator("a:has-text('Not Listesi')")
                await target_link.wait_for(state="attached")
                
                print("JavaScript ile Native Click atılıyor... 🖱️")
                await target_link.evaluate("element => element.click()")

                # 3. POPUP KONTROLÜ (SweetAlert)
                print("Popup kontrol ediliyor...")
                try:
                    popup_btn = page.locator("button.swal2-confirm")
                    # Eğer 3 sn içinde belirirse tıkla
                    if await popup_btn.count() > 0 or await popup_btn.is_visible(timeout=3000):
                        print("🚨 Duyuru popup'ı yakalandı! Kapatılıyor... 👊")
                        await popup_btn.click()
                        await page.wait_for_timeout(500)
                except:
                    print("Engelleyici popup yok, devam.")

                # --- 4. KRİTİK BÖLÜM: IFRAME AVCILIĞI 🕵️‍♂️ ---
                print("Tablo aranıyor (Frame Analizi)...")
                
                # Tabloyu tutacak değişkenimiz (Frame mi yoksa Page mi?)
                content_frame = None
                
                # Önce ana sayfaya hızlıca bir bakalım
                try:
                    await page.wait_for_selector("#grd_not_listesi", state="attached", timeout=2000)
                    content_frame = page
                    print("Tablo ana sayfada bulundu!")
                except:
                    print("Ana sayfada yok, Iframe'lere dalıyoruz...")

                # Ana sayfada yoksa, tüm iframe'leri tek tek gezelim
                if not content_frame:
                    for frame in page.frames:
                        try:
                            # Her frame'in içine bak: "Sende bu tablo var mı?"
                            # count > 0 ise bulduk demektir.
                            if await frame.locator("#grd_not_listesi").count() > 0:
                                content_frame = frame
                                print(f"Buldum! Tablo '{frame.name or 'isimsiz'}' isimli frame içinde saklanmış.")
                                break
                        except:
                            continue
                
                if not content_frame:
                    # Hata ayıklama için sayfa kaynağını kaydet
                    await page.screenshot(path="hata_iframe.png")
                    raise Exception("Kanki tabloyu yer yarıldı içine girdi sanırım, hiçbir frame'de yok!")

                # 5. TABLOYU OKU (Artık 'page' yerine 'content_frame' kullanıyoruz)
                # content_frame doğru odayı işaret ediyor.
                rows = await content_frame.locator("#grd_not_listesi tbody tr").all()
                grades = []

                for row in rows:
                    cols = await row.locator("td").all()
                    if len(cols) > 5:
                        course_text = await cols[2].inner_text()
                        
                        if not course_text.strip() or "Ders Adı" in course_text:
                            continue

                        course = course_text.strip()
                        # Boşlukları temizle
                        exam_info = (await cols[4].inner_text()).strip() 
                        letter = (await cols[6].inner_text()).strip()
                        
                        midterm = "-"
                        if "Vize" in exam_info:
                            # "Vize : 80" stringini parçala
                            parts = exam_info.split(":")
                            if len(parts) > 1:
                                # Sayıyı al ve temizle
                                midterm = parts[1].strip().split()[0]

                        final = "-"
                        if not letter: letter = "--"

                        grades.append(StudentGrade(course, midterm, final, letter))
                
                return grades

            except Exception as e:
                # Hata anını görelim
                await page.screenshot(path="hata_son.png")
                print(f"Hata detayı: {e}")
                raise e
            finally:
                await browser.close()

# --- 4. ANA PROGRAM ---
async def main():
    ui = TerminalUI()
    
    # --- Linkler ---
    scraper = UniversityScraper(
        login_url="https://obs.ozal.edu.tr/oibs/std/login.aspx",
    )

    user = Prompt.ask("Öğrenci No")
    pwd = Prompt.ask("Şifre", password=True)

    ui.console.print("\n[yellow]Sisteme bağlanılıyor... (Tarayıcı gizli modda)[/yellow]")
    
    try:
        grades = await scraper.fetch_grades(user, pwd, ui.show_captcha)
        
        ui.console.print("[green]Giriş başarılı! Notlar çekildi.[/green]\n")
        ui.display_grades(grades)
        
    except Exception as e:
        ui.show_error(f"Patladık: {e}")

if __name__ == "__main__":
    asyncio.run(main())

if __name__ == "__main__":
    asyncio.run(main())