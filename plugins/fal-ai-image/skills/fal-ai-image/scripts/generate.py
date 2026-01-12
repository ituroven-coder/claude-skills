#!/usr/bin/env python3
"""Generate images using fal.ai nano-banana model."""

import argparse
import os
import sys
from datetime import datetime
from pathlib import Path

try:
    import fal_client
except ImportError:
    print("Error: fal-client not installed. Run: pip install fal-client")
    sys.exit(1)

try:
    import requests
except ImportError:
    requests = None


def load_api_key():
    """Load FAL_KEY from config/.env or environment."""
    # Try config/.env first
    script_dir = Path(__file__).parent.parent
    env_file = script_dir / "config" / ".env"

    if env_file.exists():
        with open(env_file) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, value = line.split("=", 1)
                    if key.strip() == "FAL_KEY":
                        return value.strip()

    # Fall back to environment variable
    return os.environ.get("FAL_KEY")


def download_image(url: str, output_path: Path) -> bool:
    """Download image from URL to local path."""
    if requests is None:
        print("Warning: requests not installed, cannot download. Run: pip install requests")
        return False

    try:
        response = requests.get(url, timeout=60)
        response.raise_for_status()
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "wb") as f:
            f.write(response.content)
        return True
    except Exception as e:
        print(f"Warning: Failed to download: {e}")
        return False


def generate(
    prompt: str,
    aspect_ratio: str = "1:1",
    resolution: str = "1K",
    num_images: int = 1,
    output_format: str = "png",
    output_dir: str | None = None,
    filename: str = "generated",
    web_search: bool = False,
) -> dict:
    """Generate images using nano-banana model."""

    api_key = load_api_key()
    if not api_key:
        print("Error: FAL_KEY not found. Set in config/.env or environment.")
        sys.exit(1)

    os.environ["FAL_KEY"] = api_key

    arguments = {
        "prompt": prompt,
        "num_images": num_images,
        "aspect_ratio": aspect_ratio,
        "resolution": resolution,
        "output_format": output_format,
    }

    if web_search:
        arguments["enable_web_search"] = True

    print(f"Generating {num_images} image(s)...")
    print(f"Prompt: {prompt[:100]}{'...' if len(prompt) > 100 else ''}")
    print(f"Settings: {aspect_ratio}, {resolution}, {output_format}")
    print()

    try:
        result = fal_client.subscribe(
            "fal-ai/nano-banana",
            arguments=arguments,
        )
    except Exception as e:
        print(f"Error: Generation failed: {e}")
        sys.exit(1)

    images = result.get("images", [])
    description = result.get("description", "")

    if not images:
        print("Error: No images generated")
        sys.exit(1)

    print(f"Generated {len(images)} image(s)")
    if description:
        print(f"Description: {description}")
    print()

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    saved_paths = []

    for i, img in enumerate(images):
        url = img.get("url", "")
        suffix = f"_{i}" if len(images) > 1 else ""

        print(f"Image {i + 1}:")
        print(f"  URL: {url}")

        if output_dir and url:
            ext = output_format
            out_path = Path(output_dir) / f"{filename}_{timestamp}{suffix}.{ext}"

            if download_image(url, out_path):
                saved_paths.append(str(out_path))
                print(f"  Saved: {out_path}")

        if img.get("width") and img.get("height"):
            print(f"  Size: {img['width']}x{img['height']}")
        print()

    print("Done!")
    if saved_paths:
        print(f"Files saved to: {output_dir}")
    print("Note: URLs expire in ~1 hour")

    return {
        "images": images,
        "description": description,
        "saved_paths": saved_paths,
    }


def main():
    parser = argparse.ArgumentParser(description="Generate images with fal.ai nano-banana")
    parser.add_argument("--prompt", "-p", required=True, help="Image description")
    parser.add_argument("--aspect-ratio", "-a", default="1:1",
                        choices=["21:9", "16:9", "3:2", "4:3", "5:4", "1:1", "4:5", "3:4", "2:3", "9:16"],
                        help="Aspect ratio (default: 1:1)")
    parser.add_argument("--resolution", "-r", default="1K",
                        choices=["1K", "2K", "4K"],
                        help="Resolution (default: 1K)")
    parser.add_argument("--num-images", "-n", type=int, default=1,
                        choices=[1, 2, 3, 4],
                        help="Number of images (default: 1)")
    parser.add_argument("--output-format", "-f", default="png",
                        choices=["png", "jpeg", "webp"],
                        help="Output format (default: png)")
    parser.add_argument("--output-dir", "-o",
                        help="Directory to save images (optional)")
    parser.add_argument("--filename", default="generated",
                        help="Base filename without extension (default: generated)")
    parser.add_argument("--web-search", "-w", action="store_true",
                        help="Enable web search for generation")

    args = parser.parse_args()

    generate(
        prompt=args.prompt,
        aspect_ratio=args.aspect_ratio,
        resolution=args.resolution,
        num_images=args.num_images,
        output_format=args.output_format,
        output_dir=args.output_dir,
        filename=args.filename,
        web_search=args.web_search,
    )


if __name__ == "__main__":
    main()
