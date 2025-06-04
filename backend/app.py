from flask import Flask, request, jsonify
from flask_cors import CORS
import cv2
import numpy as np
import base64
import os
from ultralytics import YOLO
import requests
import math
import logging
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
import datetime

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# Configure requests session with retry strategy
session = requests.Session()
retry_strategy = Retry(
    total=3,
    backoff_factor=1,
    status_forcelist=[500, 502, 503, 504]
)
adapter = HTTPAdapter(max_retries=retry_strategy)
session.mount("http://", adapter)
session.mount("https://", adapter)

# Load YOLO model
try:
    # Use default YOLOv8n model
    yolo_model = YOLO('yolov8n.pt')
    logger.info("YOLO model loaded successfully")
except Exception as e:
    logger.error(f"Failed to load YOLO model: {e}")
    raise

# Constants for distance calculation
FOCAL_LENGTH = 1000  # Default focal length for distance calculation

KNOWN_WIDTHS = {
    'person': 0.5,  # Average width of a person in meters
    'car': 1.8,     # Average car width
    'truck': 2.4,   # Average truck width
    'bus': 2.5,     # Average bus width
    'motorcycle': 0.8, # Average motorcycle width
    'bicycle': 0.6, # Average bicycle width
    'bench': 0.5,   # Average bench width
    'chair': 0.5,   # Average chair width
    'dining table': 0.8, # Average table width
    'potted plant': 0.3, # Average plant width
    'tv': 0.8,      # Average TV width
    'laptop': 0.3,  # Average laptop width
    'mouse': 0.1,   # Average mouse width
    'remote': 0.1,  # Average remote width
    'keyboard': 0.3, # Average keyboard width
    'cell phone': 0.1, # Average phone width
    'book': 0.2,    # Average book width
    'clock': 0.2,   # Average clock width
    'vase': 0.2,    # Average vase width
    'scissors': 0.1, # Average scissors width
    'toothbrush': 0.1, # Average toothbrush width
    'wall': 0.2,    # Average wall thickness
    'door': 1.0,    # Average door width
    'stairs': 1.2,  # Average stairs width
}

# Ethiopian default location (Addis Ababa)
DEFAULT_LAT = 9.0320
DEFAULT_LON = 38.7489

def get_priority(object_type):
    """Get priority level for different object types"""
    priority_levels = {
        'person': 1,
        'car': 1,
        'truck': 1,
        'bus': 1,
        'motorcycle': 1,
        'bicycle': 1,
        'wall': 2,
        'door': 2,
        'stairs': 2,
        'bench': 3,
        'chair': 3,
        'dining table': 3,
        'potted plant': 4,
        'tv': 4,
        'laptop': 4,
        'mouse': 4,
        'remote': 4,
        'keyboard': 4,
        'cell phone': 4,
        'book': 4,
        'clock': 4,
        'vase': 4,
        'scissors': 4,
        'toothbrush': 4,
    }
    return priority_levels.get(object_type, 5)

def calculate_distance(pixel_width, object_type, focal_length):
    """Calculate distance using the formula: distance = (known_width * focal_length) / pixel_width"""
    try:
        known_width = KNOWN_WIDTHS.get(object_type, 0.5)  # Default to 0.5m if type unknown
        distance = (known_width * focal_length) / pixel_width
        return max(0.1, min(distance, 50))  # Limit distance between 0.1 and 50 meters
    except Exception as e:
        logger.error(f"Distance calculation error: {e}")
        return 0.0

def calculate_position(x1, x2, image_width):
    """Calculate relative position (0 to 1, where 0 is left, 0.5 is center, 1 is right)"""
    try:
        center_x = (x1 + x2) / 2
        return center_x / image_width
    except Exception as e:
        logger.error(f"Position calculation error: {e}")
        return 0.5

def get_direction(position):
    """Get direction based on position"""
    if position < 0.3:
        return "to your left"
    elif position > 0.7:
        return "to your right"
    else:
        return "in front of you"

# Replace OpenStreetMap's Nominatim and OSRM for free routing
OSRM_BASE_URL = "https://router.project-osrm.org/route/v1/driving/"
NOMINATIM_BASE_URL = "https://nominatim.openstreetmap.org/search"

@app.route('/')
def home():
    return "Object Detection API is running."

@app.route('/status')
def status():
    try:
        # Check if YOLO model is loaded
        if yolo_model is None:
            return jsonify({
                "status": "error",
                "message": "YOLO model not loaded",
                "model_loaded": False
            }), 500

        return jsonify({
            "status": "ok",
            "message": "API is running",
            "model_loaded": True,
            "endpoints": {
                "detect_objects": "/detect_objects",
                "navigate": "/navigate"
            }
        })
    except Exception as e:
        logger.error(f"Status check error: {e}")
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500

@app.route('/health')
def health():
    try:
        # Basic health check
        return jsonify({
            "status": "healthy",
            "timestamp": datetime.datetime.now().isoformat()
        })
    except Exception as e:
        logger.error(f"Health check error: {e}")
        return jsonify({
            "status": "unhealthy",
            "error": str(e)
        }), 500

@app.route('/test_detection', methods=['GET'])
def test_detection():
    """Test endpoint to verify YOLO model is working"""
    try:
        # Create a test image (black background)
        test_image = np.zeros((640, 640, 3), dtype=np.uint8)
        
        # Run detection
        results = yolo_model(test_image)
        
        return jsonify({
            "status": "success",
            "message": "YOLO model is working",
            "model_info": {
                "names": yolo_model.names,
                "device": str(yolo_model.device),
                "task": yolo_model.task
            }
        })
    except Exception as e:
        logger.error(f"Test detection error: {e}")
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500

@app.route('/detect_objects', methods=['POST'])
def detect_objects():
    try:
        logger.info("Received object detection request")
        data = request.json
        if 'image' not in data:
            logger.error("No image provided in request")
            return jsonify({"error": "No image provided"}), 400

        # Decode the base64 image
        try:
            logger.info("Decoding base64 image")
            image_data = base64.b64decode(data['image'])
            np_image = np.frombuffer(image_data, np.uint8)
            image = cv2.imdecode(np_image, cv2.IMREAD_COLOR)
            if image is None:
                logger.error("Failed to decode image")
                return jsonify({"error": "Failed to decode image"}), 400
            logger.info(f"Image decoded successfully. Shape: {image.shape}")
        except Exception as e:
            logger.error(f"Image decoding error: {e}")
            return jsonify({"error": f"Invalid image format: {str(e)}"}), 400

        # Get image dimensions
        height, width = image.shape[:2]
        logger.info(f"Processing image of size {width}x{height}")

        # Perform YOLO detection
        try:
            logger.info("Starting YOLO detection")
            results = yolo_model(image, conf=0.25)  # Lower confidence threshold for more detections
            
            if isinstance(results, list):
                results = results[0]
            
            if not hasattr(results, 'boxes'):
                logger.error("No detection boxes found in results")
                return jsonify({"error": "No detections found"}), 500
                
            boxes = results.boxes
            logger.info(f"Found {len(boxes)} detections")
            
        except Exception as e:
            logger.error(f"YOLO detection error: {e}")
            return jsonify({"error": f"Detection failed: {str(e)}"}), 500

        detections = []
        try:
            for box in boxes:
                try:
                    # Get box coordinates
                    x1, y1, x2, y2 = box.xyxy[0].tolist()
                    confidence = box.conf[0].item()
                    class_id = int(box.cls[0].item())
                    label = yolo_model.names[class_id]
                    
                    # Calculate pixel width of the detected object
                    pixel_width = x2 - x1
                    
                    # Calculate distance
                    distance = calculate_distance(pixel_width, label, FOCAL_LENGTH)
                    
                    # Calculate position
                    position = calculate_position(x1, x2, width)
                    
                    # Determine direction
                    direction = get_direction(position)
                    
                    # Get priority level
                    priority = get_priority(label)
                    
                    detection = {
                        "label": label,
                        "confidence": float(confidence),
                        "distance": round(distance, 2),
                        "direction": direction,
                        "priority": priority
                    }
                    detections.append(detection)
                    logger.info(f"Detected {label} at {distance}m {direction}")
                except Exception as e:
                    logger.error(f"Error processing detection: {e}")
                    continue

            # Sort detections by priority and distance
            detections.sort(key=lambda x: (x['priority'], x['distance']))

            logger.info(f"Returning {len(detections)} detections")
            return jsonify({"detections": detections})

        except Exception as e:
            logger.error(f"Error processing detections: {e}")
            return jsonify({"error": f"Error processing detections: {str(e)}"}), 500

    except Exception as e:
        logger.error(f"Unexpected error in detect_objects: {e}")
        return jsonify({"error": f"Unexpected error: {str(e)}"}), 500

@app.route('/navigate', methods=['POST'])
def navigate():
    try:
        logger.info("Received navigation request")
        data = request.json
        logger.info(f"Request data: {data}")

        if 'destination' not in data:
            logger.error("No destination provided")
            return jsonify({"error": "No destination provided"}), 400

        # Check for current location
        if 'current_lat' not in data or 'current_lon' not in data:
            logger.error("Current location not provided")
            return jsonify({"error": "Current location is required"}), 400

        destination = data['destination']
        current_lat = float(data['current_lat'])
        current_lon = float(data['current_lon'])
        logger.info(f"Calculating route from {current_lat}, {current_lon} to: {destination}")

        # Get destination coordinates using Nominatim
        try:
            # Add Ethiopia to the search query and handle Amharic text
            search_query = f"{destination}, Ethiopia"
            nominatim_params = {
                'q': search_query,
                'format': 'json',
                'limit': 1,
                'countrycodes': 'et',  # Restrict to Ethiopia
                'accept-language': 'am,en'  # Accept Amharic and English
            }
            logger.info(f"Requesting Nominatim with params: {nominatim_params}")
            nominatim_response = session.get(
                NOMINATIM_BASE_URL, 
                params=nominatim_params,
                timeout=5,
                headers={
                    'User-Agent': 'AssistiveNavigationApp/1.0',
                    'Accept-Language': 'am,en'  # Accept Amharic and English
                }
            )
            logger.info(f"Nominatim response status: {nominatim_response.status_code}")

            if nominatim_response.status_code != 200 or not nominatim_response.json():
                logger.error(f"Destination not found: {destination}")
                return jsonify({"error": "Destination not found in Ethiopia"}), 404

            destination_coords = nominatim_response.json()[0]
            dest_lat = float(destination_coords['lat'])
            dest_lon = float(destination_coords['lon'])
            logger.info(f"Destination coordinates: {dest_lat}, {dest_lon}")
        except Exception as e:
            logger.error(f"Error getting destination coordinates: {e}")
            return jsonify({"error": "Failed to get destination coordinates"}), 500

        # Use OSRM to calculate route
        try:
            coordinates = f"{current_lon},{current_lat};{dest_lon},{dest_lat}"
            osrm_url = f"{OSRM_BASE_URL}{coordinates}"
            
            logger.info(f"Requesting OSRM route with coordinates: {coordinates}")
            
            osrm_response = session.get(
                osrm_url,
                params={
                    'overview': 'full',
                    'geometries': 'geojson',
                    'steps': 'true',
                    'annotations': 'true',
                    'alternatives': 'true'
                },
                timeout=10,
                headers={'User-Agent': 'AssistiveNavigationApp/1.0'}
            )
            
            if osrm_response.status_code != 200:
                error_msg = f"Route calculation failed: {osrm_response.text}"
                logger.error(error_msg)
                return jsonify({"error": "Unable to calculate route. Please try again."}), 500

            route_data = osrm_response.json()
            if not route_data.get('routes'):
                logger.error("No routes found in response")
                return jsonify({"error": "No route found. The destination might be too far or unreachable."}), 404

            # Use the first available route
            route = route_data['routes'][0]['geometry']['coordinates']
            distance = route_data['routes'][0]['distance'] / 1000  # Convert to km
            duration = route_data['routes'][0]['duration'] / 60  # Convert to minutes

            # Extract and format turn-by-turn instructions
            instructions = []
            for step in route_data['routes'][0]['legs'][0]['steps']:
                maneuver = step['maneuver']
                distance_to_next = step['distance'] / 1000  # Convert to km
                
                # Get the maneuver type
                maneuver_type = maneuver.get('type', '')
                modifier = maneuver.get('modifier', '')
                
                # Create user-friendly instruction
                instruction = ""
                
                # Handle different maneuver types
                if maneuver_type == 'turn':
                    if modifier == 'left':
                        instruction = f"Turn left in {distance_to_next:.1f} kilometers"
                    elif modifier == 'right':
                        instruction = f"Turn right in {distance_to_next:.1f} kilometers"
                    elif modifier == 'slight left':
                        instruction = f"Make a slight left turn in {distance_to_next:.1f} kilometers"
                    elif modifier == 'slight right':
                        instruction = f"Make a slight right turn in {distance_to_next:.1f} kilometers"
                    elif modifier == 'sharp left':
                        instruction = f"Make a sharp left turn in {distance_to_next:.1f} kilometers"
                    elif modifier == 'sharp right':
                        instruction = f"Make a sharp right turn in {distance_to_next:.1f} kilometers"
                    else:
                        instruction = f"Turn {modifier} in {distance_to_next:.1f} kilometers"
                
                elif maneuver_type == 'continue':
                    instruction = f"Continue straight for {distance_to_next:.1f} kilometers"
                
                elif maneuver_type == 'merge':
                    instruction = f"Merge onto the road in {distance_to_next:.1f} kilometers"
                
                elif maneuver_type == 'roundabout':
                    instruction = f"Enter the roundabout and take the {modifier} exit in {distance_to_next:.1f} kilometers"
                
                elif maneuver_type == 'arrive':
                    instruction = f"You have arrived at your destination"
                
                else:
                    instruction = f"Follow the road for {distance_to_next:.1f} kilometers"
                
                instructions.append(instruction)

            navigation_data = {
                "route": route,
                "distance": f"{distance:.2f} km",
                "duration": f"{duration:.2f} mins",
                "instructions": instructions,
                "destination_coords": {
                    "lat": dest_lat,
                    "lon": dest_lon
                }
            }

            return jsonify(navigation_data)

        except Exception as e:
            logger.error(f"Error calculating route: {e}")
            return jsonify({"error": "Failed to calculate route. Please try again."}), 500

    except Exception as e:
        logger.error(f"Unexpected error in navigate: {e}")
        return jsonify({"error": "An unexpected error occurred. Please try again."}), 500

if __name__ == '__main__':
    logger.info("Starting Flask server...")
    app.run(host='0.0.0.0', port=5000, debug=True)
