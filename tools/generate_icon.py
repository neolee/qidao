from PIL import Image, ImageDraw, ImageFont
import os

def generate_icon():
    base_size = 1024
    # Slightly less faded board color (回调一点点)
    board_color = (240, 215, 180) 
    line_color = (190, 170, 150) 
    
    def create_image(size):
        scale = size / base_size
        img = Image.new('RGB', (size, size), board_color)
        draw = ImageDraw.Draw(img)
        
        # Draw grid lines
        margin = 80 * scale
        grid_size = 7 
        spacing = (size - 2 * margin) // (grid_size - 1)
        
        for i in range(grid_size):
            # Vertical
            x = margin + i * spacing
            draw.line([(x, margin), (x, size - margin)], fill=line_color, width=max(1, int(6 * scale)))
            # Horizontal
            y = margin + i * spacing
            draw.line([(margin, y), (size - margin, y)], fill=line_color, width=max(1, int(6 * scale)))
        
        # Draw some stones (faded)
        stone_radius = max(1, (spacing // 2 - int(5 * scale)))
        stones = [
            (1, 1, "black"), (1, 5, "white"),
            (5, 1, "white"), (5, 5, "black"),
            (3, 3, "white") # Changed center to white
        ]
        
        for col, row, color in stones:
            cx = margin + col * spacing
            cy = margin + row * spacing
            x0, y0 = cx - stone_radius, cy - stone_radius
            x1, y1 = cx + stone_radius, cy + stone_radius
            if x1 <= x0: x1 = x0 + 1
            if y1 <= y0: y1 = y0 + 1
            bbox = [x0, y0, x1, y1]
            if color == "black":
                draw.ellipse(bbox, fill=(120, 120, 120)) 
            else:
                draw.ellipse(bbox, fill=(250, 250, 250), outline=(220, 220, 220), width=max(1, int(2 * scale)))
            
        # Draw "道"
        font_path = "/Library/Fonts/AdobeKaitiStd-Regular.otf"
        if not os.path.exists(font_path):
            font_path = "/System/Library/Fonts/Supplemental/Songti.ttc"
            
        try:
            font = ImageFont.truetype(font_path, int(650 * scale))
        except:
            font = ImageFont.load_default()
            
        text = "道"
        bbox = draw.textbbox((0, 0), text, font=font)
        w = bbox[2] - bbox[0]
        h = bbox[3] - bbox[1]
        
        shadow_offset = 10 * scale
        draw.text(((size - w) // 2 + shadow_offset, (size - h) // 2 - 40 * scale + shadow_offset), text, font=font, fill=(0, 0, 0, 80))
        draw.text(((size - w) // 2, (size - h) // 2 - 40 * scale), text, font=font, fill=(40, 30, 20))
        return img

    output_dir = "QiDao/QiDao/Assets.xcassets/AppIcon.appiconset"
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    # Generate all sizes
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    for s in sizes:
        img = create_image(s)
        img.save(os.path.join(output_dir, f"app_{s}.png"))
    
    # Generate Contents.json
    contents = """{
  "images" : [
    { "size" : "16x16", "idiom" : "mac", "filename" : "app_16.png", "scale" : "1x" },
    { "size" : "16x16", "idiom" : "mac", "filename" : "app_32.png", "scale" : "2x" },
    { "size" : "32x32", "idiom" : "mac", "filename" : "app_32.png", "scale" : "1x" },
    { "size" : "32x32", "idiom" : "mac", "filename" : "app_64.png", "scale" : "2x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "app_128.png", "scale" : "1x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "app_256.png", "scale" : "2x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "app_256.png", "scale" : "1x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "app_512.png", "scale" : "2x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "app_512.png", "scale" : "1x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "app_1024.png", "scale" : "2x" }
  ],
  "info" : { "version" : 1, "author" : "xcode" }
}
"""
    with open(os.path.join(output_dir, "Contents.json"), "w") as f:
        f.write(contents)

if __name__ == "__main__":
    generate_icon()
