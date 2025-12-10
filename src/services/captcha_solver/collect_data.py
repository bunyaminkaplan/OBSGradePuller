import sys
import os
import uuid
import time
from rich.console import Console

# Proje kök dizinini path'e ekle
current_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.dirname(current_dir)
if project_root not in sys.path:
    sys.path.insert(0, project_root)

from src.services.obs_client import OBSClient

def main():
    console = Console()
    client = OBSClient()
    
    dataset_dir = os.path.join(project_root, "dataset")
    if not os.path.exists(dataset_dir):
        os.makedirs(dataset_dir)
        
    console.print("[bold green]OBS Captcha Veri Toplayıcı Başlatıldı![/bold green]")
    console.print("Çıkmak için [bold red]'q'[/bold red], atlamak için [bold yellow]Enter[/bold yellow] tuşuna basın.")
    console.print("Format: [cyan]Sayı1[/cyan] [magenta]s[/magenta] [cyan]Sayı2[/cyan] (Örn: 58s5 -> 58+5 olarak kaydedilir)\n")

    count = 0
    while True:
        try:
            # 1. Login sayfasına git (Cookie ve ViewState tazele)
            # Login metodu yerine manuel istek atıyoruz ki sistemi yormayalım
            # Ancak OBSClient'ın login metodundaki captcha indirme mantığını kullanmak daha temiz
            # Bu yüzden _download_captcha metodunu direkt çağıramayız (soup lazım)
            # O yüzden basit bir "sayfa yükle -> resim bul -> indir" akışı yapalım
            
            console.print("[dim]Resim indiriliyor...[/dim]", end="\r")
            
            # Login sayfasını çek
            r_get = client.session.get(client.LOGIN_URL)
            from bs4 import BeautifulSoup
            soup = BeautifulSoup(r_get.content, "html.parser")
            
            # Captcha indir
            captcha_path = client._download_captcha(soup)
            
            if not captcha_path:
                console.print("[red]Captcha bulunamadı! Tekrar deneniyor...[/red]")
                time.sleep(1)
                continue

            # Resmi aç
            import platform, subprocess
            if platform.system() == "Windows": os.startfile(captcha_path)
            elif platform.system() == "Darwin": subprocess.call(("open", captcha_path))
            else: subprocess.call(("xdg-open", captcha_path))
            
            # Kullanıcı girişi
            user_input = console.input(f"[bold yellow]#{count+1} Ne görüyorsun?[/bold yellow] (q=çık): ").strip().lower()
            
            # Dosyayı kapat/silmeye gerek yok, taşıyacağız
            
            if user_input == 'q':
                if os.path.exists(captcha_path): os.remove(captcha_path)
                console.print("\n[bold red]Çıkış yapılıyor... Teşekkürler![/bold red]")
                break
                
            if not user_input:
                console.print("[dim]Atlandı...[/dim]")
                if os.path.exists(captcha_path): os.remove(captcha_path)
                continue
                
            # 's' harfini '+' ile değiştir
            formatted_label = user_input.replace('s', '+')
            
            # 1. Ham Resmi Kaydet
            filename = f"{formatted_label}_{uuid.uuid4().hex[:8]}.png"
            target_path = os.path.join(dataset_dir, filename)
            
            # open()'dan gelen dosyayi tasimak yerine, openCV ile okuyup kaydedelim (Daha kontrollü)
            # Once cv2 ile oku
            import cv2
            import numpy as np
            
            full_img = cv2.imread(captcha_path, cv2.IMREAD_GRAYSCALE)
            cv2.imwrite(target_path, full_img) # Raw yedek
            
            # --- OTOMATİK DİLİMLEME VE RAKAM KAYDETME ---
            dataset_digits_dir = os.path.join(project_root, "dataset_digits")
            if not os.path.exists(dataset_digits_dir): os.makedirs(dataset_digits_dir)
            
            parts = formatted_label.split('+')
            # Eger format xx+x seklindeyse (ornegin 58+5)
            if len(parts) == 2 and len(parts[0]) == 2 and len(parts[1]) == 1:
                # Koordinatlar (VERIFIED)
                SLICES = [(13, 29), (29, 52), (88, 110)]
                digits_val = [int(parts[0][0]), int(parts[0][1]), int(parts[1][0])]
                
                for i, (start, end) in enumerate(SLICES):
                    digit_val = digits_val[i]
                    roi = full_img[:, start:end]
                    
                    # Kare yap & Resize 32x32
                    h, w = roi.shape
                    if w > 0 and h > 0:
                        top_bottom_pad = 0
                        left_right_pad = max(0, (h - w) // 2)
                        padded = cv2.copyMakeBorder(roi, top_bottom_pad, top_bottom_pad, left_right_pad, left_right_pad, cv2.BORDER_CONSTANT, value=0)
                        resized = cv2.resize(padded, (32, 32))
                        
                        # Klasor kontrol
                        d_folder = os.path.join(dataset_digits_dir, str(digit_val))
                        if not os.path.exists(d_folder): os.makedirs(d_folder)
                        
                        # Kaydet
                        digit_filename = f"{uuid.uuid4().hex[:8]}.png"
                        cv2.imwrite(os.path.join(d_folder, digit_filename), resized)
                
                console.print(f"✅ Kaydedildi: [cyan]{filename}[/cyan] (+ 3 Rakam Ayrıştırıldı)")
            else:
                 console.print(f"✅ Kaydedildi: [cyan]{filename}[/cyan] (Sadece Raw - Format Uymadı)")
            
            os.remove(captcha_path) # Temp dosyayi sil
            count += 1
            
        except KeyboardInterrupt:
            console.print("\n[bold red]İşlem durduruldu.[/bold red]")
            break
        except Exception as e:
            console.print(f"[red]Hata: {e}[/red]")
            time.sleep(1)

if __name__ == "__main__":
    main()
