import os
import sys

# --- 1. AYARLAR (EN TEPEDE) ---
# Playwright'a diyoruz ki: "Kanki hayal görme, tarayıcılar bilgisayarın AppData klasöründe."
os.environ["PLAYWRIGHT_BROWSERS_PATH"] = os.path.join(os.getenv('LOCALAPPDATA'), 'ms-playwright')

# --- DİĞER IMPORTLAR ---
import asyncio
import platform
import subprocess
import json
import time
import keyring # Şifreleri güvenli saklamak için
from typing import List, Callable, Optional
from dataclasses import dataclass, asdict

# Playwright Installer
from playwright.__main__ import main as playwright_cli
from playwright.async_api import async_playwright, Error as PlaywrightError

from rich.console import Console
from rich.table import Table
from rich.prompt import Prompt, Confirm
from rich.panel import Panel

# --- 2. HATA SINIFLARI ---
class CaptchaError(Exception): pass
class CredentialError(Exception): pass

# --- 3. VERİ MODELLERİ ---
@dataclass
class StudentGrade:
    course_name: str
    midterm: str
    final: str
    letter_grade: str

@dataclass
class UserConfig:
    username: str
    password: str

# --- 4. CONFIG MANAGER (KEYRING SİSTEMİ) ---
class ConfigManager:
    # Windows Kasası'nda bu isimle saklayacağız
    SERVICE_ID = "UniNotSistemi_App" 
    
    @staticmethod
    def load() -> Optional[UserConfig]:
        try:
            # Kasadan veriyi iste
            data = keyring.get_password(ConfigManager.SERVICE_ID, "user_data")
            if not data: return None
            
            # Veriyi ayır (user|pass)
            username, password = data.split("|", 1)
            return UserConfig(username, password)
        except: return None

    @staticmethod
    def save(config: UserConfig):
        # Veriyi birleştir ve kilitle
        combined = f"{config.username}|{config.password}"
        keyring.set_password(ConfigManager.SERVICE_ID, "user_data", combined)

    @staticmethod
    def delete():
        try:
            keyring.delete_password(ConfigManager.SERVICE_ID, "user_data")
        except: pass

# --- 5. ARAYÜZ KATMANI (UI) ---
class TerminalUI:
    def __init__(self):
        self.console = Console()

    def show_captcha(self, image_path: str) -> str:
        self.console.print(f"[yellow]! Captcha güvenlik resmi açılıyor...[/yellow]")
        
        if platform.system() == "Windows": os.startfile(image_path)
        elif platform.system() == "Darwin": subprocess.call(("open", image_path))
        else: subprocess.call(("xdg-open", image_path))

        return Prompt.ask("[bold cyan]Resimdeki işlemin sonucunu girin[/bold cyan]")

    def display_grades(self, grades: List[StudentGrade]):
        if not grades:
            self.console.print("[red]Görüntülenecek not bulunamadı.[/red]")
            return

        table = Table(title="🎓 Dönem Notları", border_style="blue", header_style="bold magenta")
        table.add_column("Ders Adı", style="cyan", no_wrap=True)
        table.add_column("Vize", justify="center")
        table.add_column("Final", justify="center")
        table.add_column("Harf", justify="center", style="bold")

        for grade in grades:
            # A1, A2 sistemi için renklendirme mantığı:
            # F ile başlayanlar (F1, F2, FF) veya DZ (Devamsız) ise Kırmızı.
            # Diğerleri (A1, B2, C1 vs.) Yeşil.
            is_fail = grade.letter_grade.startswith("F") or grade.letter_grade in ["DZ", "YZ", "BS"];
            color = "red" if is_fail else "green"
            
            formatted_grade = f"[{color}]{grade.letter_grade}[/{color}]"
            table.add_row(grade.course_name, grade.midterm, grade.final, formatted_grade)

        self.console.print(table)
        
    def show_error(self, message: str):
        self.console.print(Panel(message, title="Hata", style="bold red"))
        
    def show_success(self, message: str):
        self.console.print(f"[bold green]✅ {message}[/bold green]")
        
    def show_warning(self, message: str):
        self.console.print(f"[bold yellow]⚠️ {message}[/bold yellow]")

# --- 6. OTO-KURULUM MODÜLÜ ---
def ensure_browsers_installed(ui: TerminalUI):
    browser_path = os.environ["PLAYWRIGHT_BROWSERS_PATH"]
    # Klasör yoksa veya boşsa indir
    if not os.path.exists(browser_path) or not os.listdir(browser_path):
        ui.console.print(Panel("[bold yellow]İlk çalıştırma: Gerekli tarayıcı motorları indiriliyor...\nBu işlem bir kez yapılır, lütfen kapatmayın![/bold yellow]", title="Kurulum"))
        try:
            playwright_cli(["install", "chromium"])
            ui.show_success("Kurulum tamamlandı!")
        except Exception as e:
            ui.show_error(f"Kurulum hatası: {e}")
            sys.exit(1)

# --- 7. SCRAPER SERVİSİ ---
class UniversityScraper:
    def __init__(self, login_url: str):
        self.login_url = login_url

    async def fetch_grades(self, user_config: UserConfig, ui: TerminalUI) -> List[StudentGrade]:
        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            context = await browser.new_context(viewport={"width": 1920, "height": 1080})
            page = await context.new_page()

            try:
                # --- A. GİRİŞ İŞLEMLERİ ---
                with ui.console.status("[bold green]Öğrenci bilgi sistemine bağlanılıyor...[/bold green]", spinner="dots"):
                    await page.goto(self.login_url)
                    await page.fill("#txtParamT01", user_config.username)
                    
                    await page.click("#txtParamT02", force=True)
                    await page.evaluate("document.getElementById('txtParamT02').removeAttribute('readonly')")
                    await page.fill("#txtParamT02", user_config.password)   

                # Captcha Kontrolü
                if await page.locator("#imgCaptchaImg").count() > 0:
                    temp_img = "captcha.png"
                    await page.locator("#imgCaptchaImg").screenshot(path=temp_img)
                    
                    code = ui.show_captcha(temp_img) 
                    
                    await page.fill("#txtSecCode", code) 
                    await page.click("body", force=True) 
                    if os.path.exists(temp_img): os.remove(temp_img)

                with ui.console.status("[bold green]Giriş yapılıyor...[/bold green]", spinner="earth"):
                    # Butonun aktif olmasını bekle
                    try:
                        await page.wait_for_selector("#btnLogin:not(.disabled)", state="visible", timeout=15000)
                    except: pass

                    await page.click("#btnLogin", force=True) 
                    
                    # --- POLLING (AKILLI BEKLEME) ---
                    max_retries = 20
                    login_success = False
                    
                    for _ in range(max_retries):
                        if "login.aspx" not in page.url:
                            login_success = True
                            break

                        # Hata Analizi
                        try:
                            body_text = (await page.inner_text("body")).lower()
                            if "güvenlik kodu hatalı" in body_text or "hatalı girildi" in body_text:
                                raise CaptchaError("Güvenlik kodu (Captcha) yanlış girildi.")
                            
                            if ("kullanıcı adı" in body_text or "şifre" in body_text) and "hatalı" in body_text:
                                raise CredentialError("Öğrenci numarası veya şifre hatalı.")
                            
                            if await page.locator(".swal2-content").count() > 0:
                                popup_text = (await page.locator(".swal2-content").inner_text()).lower()
                                if "güvenlik" in popup_text: raise CaptchaError("Güvenlik kodu yanlış.")
                                if "şifre" in popup_text: raise CredentialError("Bilgiler hatalı.")
                        except (CaptchaError, CredentialError):
                            raise
                        except: pass

                        await page.wait_for_timeout(500)

                    if "login.aspx" in page.url and not login_success:
                        raise Exception("Giriş zaman aşımına uğradı.")
                
                # --- MENÜ VE POPUP İŞLEMLERİ ---
                with ui.console.status("[bold cyan]Menüler geziliyor ve popup'lar kapatılıyor...[/bold cyan]", spinner="bouncingBall"):
                    # Menü Tıklama
                    target_link = page.locator("a:has-text('Not Listesi')")
                    await target_link.wait_for(state="attached", timeout=10000)
                    await target_link.evaluate("element => element.click()")

                    # Popup'ı Kapat
                    try:
                        popup_btn = page.locator("button.swal2-confirm")
                        if await popup_btn.count() > 0:
                             await popup_btn.click(timeout=2000)
                             await page.wait_for_timeout(500)
                    except: pass 

                    # Not Tablosu Arama (Iframe Dahil)
                    content_frame = None
                    try:
                        await page.wait_for_selector("#grd_not_listesi", state="attached", timeout=2000)
                        content_frame = page
                    except: pass

                    if not content_frame:
                        for frame in page.frames:
                            try:
                                if await frame.locator("#grd_not_listesi").count() > 0:
                                    content_frame = frame
                                    break
                            except: continue
                    
                    if not content_frame:
                        raise Exception("Not tablosu bulunamadı!")

                    # Veriyi Okuma
                    rows = await content_frame.locator("#grd_not_listesi tbody tr").all()
                    grades = []

                    for row in rows:
                        cols = await row.locator("td").all()
                        if len(cols) > 5:
                            course_text = await cols[2].inner_text()
                            if not course_text.strip() or "Ders Adı" in course_text: continue
                            
                            course = course_text.strip()
                            exam_info = (await cols[4].inner_text()).strip() 
                            letter = (await cols[6].inner_text()).strip()
                            midterm = exam_info.split(":")[1].strip().split()[0] if "Vize" in exam_info and ":" in exam_info else "-"
                            final = "-"
                            if not letter: letter = "--"
                            grades.append(StudentGrade(course, midterm, final, letter))
                    
                    return grades

            except (CaptchaError, CredentialError): raise 
            except Exception as e: raise e
            finally: await browser.close()

# --- 8. ANA PROGRAM ---
async def main():
    ui = TerminalUI()
    
    # --- Tarayıcı Kontrolü ---
    ensure_browsers_installed(ui)

    scraper = UniversityScraper(login_url="https://obs.ozal.edu.tr/oibs/std/login.aspx")

    while True:
        # Config Manager artık Keyring kullanıyor
        user_config = ConfigManager.load()
        is_from_file = True

        if user_config:
            ui.console.print(f"\n[green]Kayıtlı kullanıcı bulundu: {user_config.username}[/green]")
            if not Confirm.ask("Bu kullanıcı ile devam edilsin mi?"):
                ConfigManager.delete()
                user_config = None
                is_from_file = False
        else:
            is_from_file = False

        if not user_config:
            username = Prompt.ask("Öğrenci No")
            password = Prompt.ask("Şifre", password=True)
            user_config = UserConfig(username, password)

        while True:
            try:
                grades = await scraper.fetch_grades(user_config, ui)
                
                ui.show_success("Notlar başarıyla çekildi.")
                ui.display_grades(grades)

                if not is_from_file:
                    if Confirm.ask("Bilgiler güvenli kasaya (Keyring) kaydedilsin mi?"):
                        ConfigManager.save(user_config)
                        ui.show_success("Bilgiler kaydedildi.")
                
                # --- Çıkış Bekleme ---
                ui.console.print("\n[bold]Çıkış yapmak için Enter tuşuna basınız...[/bold]")
                input()
                return 

            except CaptchaError:
                ui.show_warning("Güvenlik kodu yanlış. Tekrar deneniyor...")
                if Confirm.ask("Tekrar denemek ister misin?"): continue
                else: return 

            except CredentialError:
                ui.show_error("Kullanıcı adı veya şifre hatalı!")
                if is_from_file: ConfigManager.delete()
                break 

            except Exception as e:
                ui.show_error(f"Beklenmedik hata: {str(e)}")
                ui.console.print("\n[bold red]Programı kapatmak için Enter'a basınız...[/bold red]")
                input()
                return

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass