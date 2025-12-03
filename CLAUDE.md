# Settee - Project Documentation

## Overview

Settee is a dating/social matching application designed to help users find meaningful connections. The app uses a modern full-stack architecture with a Flutter frontend and Django REST API backend, with a PostgreSQL database for persistence.

### Project Tagline
A location-based and preference-aware matching platform with real-time messaging, discovery, and group matching capabilities.

---

## Technology Stack

### Frontend
- **Framework**: Flutter (Dart)
- **Version**: SDK ^3.8.0
- **UI Libraries**:
  - Material Design (dark theme)
  - Custom fonts (SF Pro family)
  - Google Fonts integration
  
- **Key Dependencies**:
  - `http`: REST API communication
  - `shared_preferences`: Local data persistence
  - `web_socket_channel`: Real-time messaging
  - `image_picker` & `camera`: Profile photo capture
  - `in_app_purchase`: Monetization features (Super Like, Message Like, Boosts, etc.)
  - `flutter_markdown`: Content rendering
  - `uuid`: Unique identifier generation
  - `permission_handler`: Camera/photo permissions

### Backend
- **Framework**: Django 4.2.20 with Django REST Framework
- **Language**: Python 3.13.3
- **Database**: PostgreSQL (latest)
- **Key Dependencies**:
  - `djangorestframework`: REST API framework
  - `django-cors-headers`: Cross-origin resource sharing
  - `gunicorn`: Production WSGI server
  - `psycopg2`: PostgreSQL adapter
  - `python-dotenv`: Environment variable management

### Infrastructure
- **Containerization**: Docker & Docker Compose
- **Web Server**: Nginx (reverse proxy)
- **Database**: PostgreSQL (containerized)
- **Deployment**: Docker containers with volume mounts for development

---

## Project Structure

### Directory Layout

```
Settee/
├── settee_ui/                 # Flutter mobile application
│   ├── lib/
│   │   ├── main.dart          # App entry point
│   │   └── screens/           # Screen widgets (40+ screens)
│   ├── assets/                # Images, logos, area photos
│   ├── fonts/                 # SF Pro font family
│   ├── pubspec.yaml           # Flutter dependencies
│   ├── analysis_options.yaml   # Dart linting rules
│   └── web/                   # Web build assets
│
├── settee_server/             # Django REST API backend
│   ├── manage.py              # Django CLI
│   ├── settee_config/         # Django project settings
│   │   ├── settings.py        # Project configuration
│   │   ├── urls.py            # API route definitions
│   │   ├── wsgi.py            # WSGI application
│   │   └── asgi.py            # ASGI application
│   ├── settee_app/            # Main Django app
│   │   ├── models.py          # Database models
│   │   ├── views.py           # API endpoint handlers
│   │   ├── serializers.py     # Data serialization/validation
│   │   ├── management/        # Custom management commands
│   │   └── migrations/        # Database migrations
│   ├── images/                # User uploaded profile images
│   ├── docker-compose.yml     # Multi-container configuration
│   ├── Dockerfile             # Django container definition
│   └── requirements.txt        # Python dependencies
│
├── Settee/                    # Legacy/alternative Django instance (duplicate)
└── key/                       # SSH keys directory (gitignored)
```

### Key Directories Explained

#### Frontend: `settee_ui/`
- **Purpose**: Flutter mobile app for iOS, Android, and Web
- **Main Application**: Implements dark theme, custom SF Pro font
- **Screens**: Organized in `lib/screens/` directory with 40+ screen widgets
- **Assets**: Logo, location images (Ikebukuro, Shinjuku, Shibuya, Yokohama), feature graphics
- **Build System**: Flutter build tools (pubspec.yaml manages dependencies)

#### Backend: `settee_server/`
- **Purpose**: REST API backend serving Flutter client
- **Configuration**: Django settings (postgresql, CORS, static files)
- **API Routes**: 20+ endpoints for user management, matching, messaging
- **Database**: PostgreSQL with ORM models
- **Image Storage**: Local file system under `images/` directory

---

## Core Data Models

### UserProfile
The central user model with extensive profile information:
- **Authentication**: phone, email, user_id, password (hashed)
- **Personal**: gender, birth_date, nickname, occupation, university
- **Physical**: height, blood_type, drinking, smoking
- **Preferences**: selected_area (ArrayField), match_multiple (single/group matching)
- **Availability**: available_dates (7-day rolling window)
- **Database**: PostgreSQL with ArrayField support for lists

### LikeAction
Tracks user interactions:
- **Like Types**: 0=Like, 1=Super Like, 2=Gochiso Like (treat), 3=Message Like
- **Relationship**: ForeignKey to sender and receiver UserProfile
- **Unique Constraint**: One like action per sender-receiver pair

### Message
Real-time messaging system:
- **Content**: Text messages between users
- **Ordering**: Chronological by timestamp
- **Relationships**: sender and receiver ForeignKeys

---

## API Endpoints (Backend)

### Authentication
- `POST /register/` - User registration
- `POST /login/` - User login
- `POST /upload-image/` - Profile photo upload

### User Discovery
- `GET /recommended-users/<user_id>/` - Get personalized recommendations
- `GET /popular-users/<current_user_id>/` - Trending users
- `GET /recent-users/<current_user_id>/` - Recently joined users
- `GET /matched-users/<current_user_id>/` - Mutual matches

### Interactions
- `POST /like/` - Send like/super like/other interaction
- `GET /get-profile/<user_id>/` - Fetch user profile

### Messaging
- `POST /messages/send/` - Send message
- `GET /messages/<user1_id>/<user2_id>/` - Get message history

### Profile Management
- `GET /user-profile/<user_id>/` - Get available dates
- `POST /user-profile/<user_id>/update-available-dates/` - Update availability
- `GET /user-profile/<user_id>/areas/` - Get selected areas
- `POST /user-profile/<user_id>/update-areas/` - Update area preferences
- `POST /user-profile/<user_id>/update-match-multiple/` - Toggle single/group matching
- `POST /update-profile/<user_id>/` - Update user profile

---

## Key Architectural Patterns

### Frontend Architecture
1. **Screen-Based Navigation**: Uses Flutter's MaterialApp with Navigator for screen transitions
2. **Local Persistence**: SharedPreferences for user_id, auth tokens, admin credentials
3. **Stateful Widgets**: Manages login state, discovery filtering, chat state
4. **Image Handling**: Local caching with image_picker, file-based storage
5. **Real-time Features**: WebSocket integration via `web_socket_channel`
6. **State Management**: Direct widget state management (no provider/bloc)

### App Flow
```
SplashScreen
  ├─ Check user_id in SharedPreferences
  ├─ If admin: AdminScreen (with token validation)
  ├─ If logged in: ProfileBrowseScreen (main discovery)
  └─ If not logged in: WelcomeScreen
       ├─ RegisterFlow: Consent → Details → Area Selection → Birth Date → Gender
       └─ LoginFlow: Login Method → Email/ID + Password
```

### Backend Architecture
1. **REST API Pattern**: Function-based views with DRF decorators
2. **CORS Enabled**: Allows requests from any origin (development configuration)
3. **PostgreSQL ArrayField**: Stores location preferences and available dates as arrays
4. **Password Hashing**: Django's PBKDF2-SHA256 for security
5. **Image Organization**: User images stored as `images/<user_id>/<user_id>_<index>.<ext>`
6. **Transaction Safety**: Database constraints prevent duplicate like actions

### Authentication Flow
- Phone number or user_id for login
- Password hashing with Django's built-in utilities
- Admin access via short-lived tokens (expiration tracked in SharedPreferences)

---

## Common Development Commands

### Flutter Frontend

#### Setup & Build
```bash
# Clean build artifacts
flutter clean

# Get dependencies
cd settee_ui && flutter pub get

# Run on connected device/emulator
flutter run

# Run web version on port 5555
flutter run -d web --web-port 5555

# Build release APK (Android)
flutter build apk --release

# Build release IPA (iOS)
flutter build ios --release
```

#### Code Quality
```bash
# Analyze code for issues
cd settee_ui && flutter analyze

# Format code
cd settee_ui && dart format lib/

# Run tests
cd settee_ui && flutter test
```

### Django Backend

#### Setup & Initialization
```bash
# Install dependencies
pip install -r requirements.txt

# Create database migrations
python manage.py makemigrations

# Apply migrations
python manage.py migrate

# Create superuser for admin
python manage.py createsuperuser

# Collect static files
python manage.py collectstatic
```

#### Development Server
```bash
# Run development server (port 8000)
python manage.py runserver 0.0.0.0:8000

# Run development server with custom port
python manage.py runserver 0.0.0.0:9000
```

#### Testing & Code Quality
```bash
# Run tests
python manage.py test

# Check for issues
python manage.py check

# Database shell
python manage.py dbshell
```

### Docker Deployment

#### Local Development with Docker Compose
```bash
cd settee_server

# Build and start containers
docker-compose up -d

# View logs
docker-compose logs -f

# Stop containers
docker-compose down

# Rebuild containers
docker-compose up --build -d
```

#### Database Management
```bash
# Access PostgreSQL shell
docker-compose exec settee_db psql -U myuser -d mydb

# Backup database
docker-compose exec settee_db pg_dump -U myuser mydb > backup.sql

# Restore database
docker-compose exec -T settee_db psql -U myuser mydb < backup.sql
```

### Combined Setup (Full Local Environment)

```bash
# 1. Clone and navigate
git clone git@github.com:ebaoacho/Settee.git
cd Settee

# 2. Start backend (Docker)
cd settee_server
docker-compose up -d
# Wait for PostgreSQL to be ready (check: docker-compose logs)

# 3. Apply migrations
docker-compose exec settee_django python manage.py migrate

# 4. Start frontend
cd ../settee_ui
flutter pub get
flutter run  # or flutter run -d web --web-port 5555
```

---

## Features & Functionality

### Core Features
1. **User Registration & Login**
   - Phone number or user_id authentication
   - Email verification (optional flow)
   - Password security with hashing

2. **Discovery System**
   - Recommended users (algorithm-based)
   - Popular users (most liked)
   - Recent users (newest members)
   - Filter by area, age, preferences

3. **Matching & Interactions**
   - Standard Like
   - Super Like (premium)
   - Message Like (premium)
   - Gochiso Like/Treat Like (premium)
   - Single vs. Group matching modes

4. **Messaging**
   - Real-time messaging via WebSocket
   - Message history retrieval
   - Like notification system
   - Match notifications on home screen

5. **Profile Management**
   - Profile photo upload
   - Availability calendar (7-day window)
   - Area/station preferences (Ikebukuro, Shinjuku, Shibuya, Yokohama)
   - Detailed profile info (occupation, university, blood type, height, drinking/smoking)

6. **Monetization**
   - In-app purchases via StoreKit
   - Premium features (Super Like, Message Like, Boosts)
   - Subscription model (Settee Plus)

7. **Admin Panel**
   - Admin screen with token-based access
   - Short-lived access tokens stored in SharedPreferences

---

## Important Conventions & Rules

### Code Organization
- **Flutter Screens**: Each screen is a separate `.dart` file in `lib/screens/`
- **Naming**: CamelCase for classes, snake_case for files
- **Theme**: Dark theme with black background, white text, SF Pro font family

### API Communication
- **Base URL**: Configured in individual screen files
- **Request Format**: JSON with appropriate content-type headers
- **Error Handling**: REST status codes (201 Created, 400 Bad Request, 404 Not Found, etc.)

### Database Conventions
- **Model Names**: PascalCase in Django (UserProfile, LikeAction, Message)
- **Table Names**: snake_case in Meta class (user_profile, like_action, message)
- **Field Naming**: snake_case throughout
- **Primary Keys**: Auto-incrementing BigAutoField

### Git Workflow
- Feature branches from main
- Pull requests for merging
- Commit messages describe the feature (e.g., "Added Subscription Functions", "Added Group Functions")
- Recent features: Subscription management, Group matching, Match notifications

### Linting & Analysis
- Flutter projects use `flutter_lints` with recommended rules
- Dart analysis configured in `analysis_options.yaml`
- Optional rules can be enabled/disabled per project needs

---

## Development Notes

### Areas of Recent Work
- Subscription functions implementation
- Group matching feature
- Match notifications (display match count on home screen)
- Points system when matching
- Real-time chat functionality
- Admin panel with token-based access

### Known Patterns
1. **Admin Authentication**: Short-lived tokens (stored with expiration timestamp)
2. **Image Storage**: Organized by user_id, numbered sequentially
3. **Date Availability**: Automatically normalized to 7-day rolling window
4. **WebSocket Messaging**: Real-time message delivery vs. REST API history

### Environment Configuration
- Database credentials: Environment variables (`.env` file)
- Debug mode: Enabled in development (DEBUG=True)
- CORS: All origins allowed in development
- Language: Japanese locale (LANGUAGE_CODE='ja', TIME_ZONE='Asia/Tokyo')

---

## Testing & Debugging

### Flutter Debugging
- Use Flutter DevTools: `flutter pub global activate devtools && devtools`
- Hot reload: `r` in CLI during `flutter run`
- Hot restart: `R` in CLI
- Web debugging: Chrome DevTools integration

### Django Debugging
- Print debugging with print() statements (visible in console)
- Django admin interface: `http://localhost:8000/admin/`
- Error messages included in API responses
- Database shell for complex queries: `python manage.py dbshell`

### Network Debugging
- Network requests: Use Charles Proxy or Postman
- API endpoint testing: HTTP client (request.http in project root)
- Real-time messaging: Monitor WebSocket connections

---

## Deployment Considerations

### Production Checklist
1. [ ] Set DEBUG=False in Django settings
2. [ ] Configure ALLOWED_HOSTS for domain
3. [ ] Restrict CORS_ALLOWED_ORIGINS to specific domains
4. [ ] Use strong SECRET_KEY
5. [ ] Configure PostgreSQL with proper credentials
6. [ ] Set up HTTPS/SSL certificates
7. [ ] Configure static files serving (CDN or whitespace)
8. [ ] Set up image storage (S3 or similar for production)
9. [ ] Configure email for password reset
10. [ ] Set up monitoring and error tracking

---

## Resources & References

### Flutter Documentation
- [Flutter Getting Started](https://flutter.dev/docs/get-started)
- [Dart Documentation](https://dart.dev/guides)
- [Material Design](https://material.io/design)

### Django Documentation
- [Django REST Framework](https://www.django-rest-framework.org/)
- [Django Models](https://docs.djangoproject.com/en/4.2/topics/db/models/)
- [PostgreSQL Support](https://docs.djangoproject.com/en/4.2/ref/contrib/postgres/)

### Development Tools
- [Flutter DevTools](https://flutter.dev/docs/development/tools/devtools)
- [Postman](https://www.postman.com/) - API testing
- [pgAdmin](https://www.pgadmin.org/) - PostgreSQL management

---

## Project Repository

- **Repository**: https://github.com/ebaoacho/Settee
- **Owner**: ebaoacho
- **Git Remote**: git@github.com:ebaoacho/Settee.git
- **Main Branch**: main

---

Last Updated: October 25, 2024
