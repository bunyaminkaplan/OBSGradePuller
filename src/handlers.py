import time
import os
import subprocess
import platform
from src.services.captcha_solver.captcha_solver import CaptchaSolver

def create_captcha_handler(ui_manager, status_context):
    """
    Creates a captcha handler function that fits the signature expected by OBSClient.
    Args:
        ui_manager: DisplayManager instance for user interaction.
        status_context: The active rich status context (spinner) to pause/resume.
    """
    def handler(path: str) -> str:
        # 1. Önce AI ile çözmeye çalış
        ai_result = None
        try:
            solver = CaptchaSolver()
            ai_result = solver.solve(path)
        except Exception as err:
            # Model hatası varsa yut, manuele düş
            pass 
        
        # EĞER AI ÇÖZDÜYSE DİREKT DÖNDÜR (OTOMASYON)
        if ai_result:
            ui_manager.console.print(f"[bold cyan]🤖 AI Otomatik Çözdü: {ai_result}[/bold cyan]")
            # Kısa bir bekleme (kullanıcının görmesi için)
            time.sleep(0.5)
            return ai_result

        # --- AI BAŞARISIZ İSE MANUEL GİRİŞ ---
        ui_manager.console.print("[yellow]⚠️ AI Okuyamadı, Manuel Giriş Gerekiyor![/yellow]")
        
        # Resmi işletim sisteminde aç
        if platform.system() == "Windows": os.startfile(path)
        elif platform.system() == "Darwin": subprocess.call(("open", path))
        else: subprocess.call(("xdg-open", path))
        
        ui_manager.console.print(f"[yellow]Captcha açıldı ({path})...[/yellow]")
        
        # --- KRİTİK HAMLE: Animasyonu durdur ---
        # Input alırken terminalin karışmaması için spinner durmalı
        if status_context:
            status_context.stop()
        
        prompt = "Captcha Kodu"
        code = ui_manager.ask_input(prompt)
        
        # Input bitti, animasyonu tekrar başlat
        if status_context:
            status_context.start()
        # ---------------------------------------
        
        return code

    return handler
