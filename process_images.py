import os
import sys
import subprocess

# Auto-install Pillow if not present
try:
    from PIL import Image
except ImportError:
    print("Pillow not found. Installing Pillow...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "Pillow"])
    from PIL import Image

def process_assets():
    brain_dir = r"C:\Users\heysa\.gemini\antigravity-ide\brain\9ecc5816-af5a-4e36-a4f9-a5b37e5e4fa1"
    output_dir = r"C:\Users\heysa\Documents\Dev\EasyConnect\assets\playstore"
    
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
        
    print(f"Creating output directory: {output_dir}")
    
    # 1. Resize App Icon (1024x1024 -> 512x512)
    icon_path = r"C:\Users\heysa\Documents\Dev\EasyConnect\assets\icon\app_icon.png"
    if os.path.exists(icon_path):
        print("Processing App Icon...")
        img = Image.open(icon_path)
        img_resized = img.resize((512, 512), Image.Resampling.LANCZOS)
        img_resized.save(os.path.join(output_dir, "app_icon_512.png"), "PNG")
        print("Saved: app_icon_512.png")
    else:
        print(f"ERROR: App icon not found at {icon_path}")

    # 2. Crop Feature Graphic (1024x1024 -> 1024x500)
    # Symmetrically crop height: 1024 -> 500 (remove 262px from top & bottom)
    feature_path = os.path.join(brain_dir, "easyconnect_perfect_feature_graphic_real_icon_1780904324351.png")
    if os.path.exists(feature_path):
        print("Processing Feature Graphic...")
        img = Image.open(feature_path)
        cropped_img = img.crop((0, 262, 1024, 762)) # Left, Top, Right, Bottom
        cropped_img.save(os.path.join(output_dir, "feature_graphic_1024x500.png"), "PNG")
        print("Saved: feature_graphic_1024x500.png")
    else:
        print(f"ERROR: Feature graphic not found at {feature_path}")

    # 3. Crop Framed Screenshots (1024x1024 -> 576x1024) to meet 9:16 aspect ratio
    # Symmetrically crop width: 1024 -> 576 (remove 224px from left & right)
    screenshot_files = [
        ("easyconnect_perfect_screenshot_1_1780904128161.png", "screenshot_1_framed.png"),
        ("easyconnect_perfect_screenshot_2_1780904143552.png", "screenshot_2_framed.png"),
        ("easyconnect_perfect_screenshot_3_1780904161362.png", "screenshot_3_framed.png")
    ]
    
    for filename, output_name in screenshot_files:
        path = os.path.join(brain_dir, filename)
        if os.path.exists(path):
            print(f"Processing screenshot {filename}...")
            img = Image.open(path)
            cropped_img = img.crop((224, 0, 800, 1024)) # Left, Top, Right, Bottom
            cropped_img.save(os.path.join(output_dir, output_name), "PNG")
            print(f"Saved: {output_name}")
        else:
            print(f"ERROR: Screenshot not found at {path}")

    print("\nProcessing complete! All resized and cropped assets are saved in:")
    print(output_dir)

if __name__ == "__main__":
    process_assets()
