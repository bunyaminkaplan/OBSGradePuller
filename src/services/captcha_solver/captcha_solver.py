import tensorflow as tf
import cv2
import numpy as np
import os

class CaptchaSolver:
    MODEL_PATH = os.path.join(os.path.dirname(__file__), "digit_model.h5")
    IMG_HEIGHT = 40
    IMG_WIDTH = 100
    
    # Egitimdeki dilimleme ile ayni olmali
    SLICES = [
        (13, 29), 
        (29, 52),
        (88, 110)
    ]

    def __init__(self):
        self.model = None
        self._load_model()

    def _load_model(self):
        if os.path.exists(self.MODEL_PATH):
            try:
                self.model = tf.keras.models.load_model(self.MODEL_PATH, compile=False)
                print("[INFO] Rakam Modeli Yüklendi.")
            except Exception as e:
                print(f"[HATA] Model yüklenemedi: {e}")
        else:
            print("[UYARI] Model dosyası bulunamadı.")

    def solve(self, image_path: str) -> str:
        if not self.model:
            return None

        try:
            # 1. Okuma & Preprocessing (RAW - Filtersiz)
            img = cv2.imread(image_path, cv2.IMREAD_GRAYSCALE)
            if img is None: return None
            
            # Gürültü temizleme KALDIRILDI (Training verisi de raw)
            # img = cv2.medianBlur(img, 3) 
            # ...
            
            # RESIZE KALDIRILDI - Egitim verisi orjinal boyutlarda (177x40) hazirlandi
            #img = cv2.resize(img, (self.IMG_WIDTH, self.IMG_HEIGHT))

            # 2. Dilimleme ve Tahmin
            digits = []
            for start, end in self.SLICES:
                roi = img[:, start:end]
                
                # Kare yap (32x32) - Padding ile
                h, w = roi.shape
                if w == 0 or h == 0: continue
                
                top_bottom_pad = 0
                left_right_pad = max(0, (h - w) // 2)
                padded = cv2.copyMakeBorder(roi, top_bottom_pad, top_bottom_pad, left_right_pad, left_right_pad, cv2.BORDER_CONSTANT, value=0)
                
                # Resize 32x32 (Model girdisi)
                resized = cv2.resize(padded, (32, 32))
                resized = resized / 255.0 # Normalize
                
                # Batch dim ekle (1, 32, 32, 1)
                blob = np.expand_dims(resized, axis=-1)
                blob = np.expand_dims(blob, axis=0)
                
                # Tahmin
                preds = self.model.predict(blob, verbose=0)
                digit = np.argmax(preds)
                digits.append(digit)
            
            if len(digits) != 3:
                print(f"[HATA] Beklenen 3 rakam bulunamadı, bulunan: {len(digits)}")
                return None

            # 3. Sonuç Oluşturma
            # xx + x formati
            d1, d2, d3 = digits
            num1 = (d1 * 10) + d2
            num2 = d3
            result = num1 + num2
            
            print(f"[AI TAHMİN] {d1}{d2} + {d3} = {result}")
            return str(result)
            
        except Exception as e:
            print(f"[HATA] Çözüm hatası: {e}")
            return None
