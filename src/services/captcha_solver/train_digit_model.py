import tensorflow as tf
from tensorflow.keras import layers, models
import os

DATASET_DIR = "dataset_digits"
MODEL_PATH = "src/services/digit_model.h5"
IMG_SIZE = (32, 32)
BATCH_SIZE = 16
EPOCHS = 35

def main():
    if not os.path.exists(DATASET_DIR):
        print("Hata: Dataset digits klasörü yok!")
        return

    # Keras'ın built-in loader'ı ile klasörden yükle
    # dataset_digits/0/*.png -> class 0
    train_ds = tf.keras.preprocessing.image_dataset_from_directory(
        DATASET_DIR,
        validation_split=0.2,
        subset="training",
        seed=123,
        image_size=IMG_SIZE,
        batch_size=BATCH_SIZE,
        color_mode='grayscale'
    )

    val_ds = tf.keras.preprocessing.image_dataset_from_directory(
        DATASET_DIR,
        validation_split=0.2,
        subset="validation",
        seed=123,
        image_size=IMG_SIZE,
        batch_size=BATCH_SIZE,
        color_mode='grayscale'
    )

    # Normalize et (0-255 -> 0-1)
    normalization_layer = layers.Rescaling(1./255)
    train_ds = train_ds.map(lambda x, y: (normalization_layer(x), y))
    val_ds = val_ds.map(lambda x, y: (normalization_layer(x), y))

    # Model
    model = models.Sequential([
        layers.Input(shape=(32, 32, 1)),
        layers.Conv2D(32, 3, activation='relu'),
        layers.MaxPooling2D(),
        layers.Conv2D(64, 3, activation='relu'),
        layers.MaxPooling2D(),
        layers.Flatten(),
        layers.Dense(64, activation='relu'),
        layers.Dense(10, activation='softmax')
    ])

    model.compile(optimizer='adam',
                  loss=tf.keras.losses.SparseCategoricalCrossentropy(),
                  metrics=['accuracy'])

    model.summary()

    print("Model eğitiliyor...")
    model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=EPOCHS
    )

    model.save(MODEL_PATH)
    print(f"Model kaydedildi: {MODEL_PATH}")

if __name__ == "__main__":
    main()
