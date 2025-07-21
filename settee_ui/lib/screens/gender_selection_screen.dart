import 'package:flutter/material.dart';
import 'birth_date_input_screen.dart';

class GenderSelectionScreen extends StatefulWidget {
  final String phone;
  final String email;

  const GenderSelectionScreen({
    super.key,
    required this.phone,
    required this.email,
  });

  @override
  State<GenderSelectionScreen> createState() => _GenderSelectionScreenState();
}

class _GenderSelectionScreenState extends State<GenderSelectionScreen> {
  String? selectedGender; // '男性' または '女性'

  void selectGender(String gender) {
    setState(() {
      selectedGender = gender;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16.0, top: 16.0),
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // 進捗バー
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Row(
                children: List.generate(8, (index) {
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 4,
                      decoration: BoxDecoration(
                        color: index == 0 ? Colors.green : Colors.white,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 60),
            const Text(
              'あなたの性別は？',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '登録した性別は変更できません',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 40),
            // 性別選択
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _GenderOption(
                  imagePath: 'assets/male_icon.png',
                  label: '男性',
                  isSelected: selectedGender == '男性',
                  onTap: () => selectGender('男性'),
                ),
                _GenderOption(
                  imagePath: 'assets/female_icon.png',
                  label: '女性',
                  isSelected: selectedGender == '女性',
                  onTap: () => selectGender('女性'),
                ),
              ],
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                onPressed: selectedGender != null
                    ? () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => BirthDateInputScreen(
                              phone: widget.phone,
                              email: widget.email,
                              gender: selectedGender!,
                            ),
                          ),
                        );
                      }
                    : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selectedGender != null
                        ? Colors.green
                        : Colors.grey[800],
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[800],
                    disabledForegroundColor: Colors.white54,
                    shape: const RoundedRectangleBorder(),
                  ),
                  child: const Text('次へ', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenderOption extends StatelessWidget {
  final String imagePath;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _GenderOption({
    required this.imagePath,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: isSelected ? Colors.white : Colors.grey[700],
            child: ClipOval(
              child: isSelected
                  ? Image.asset(
                      imagePath,
                      width: 80,
                      height: 80,
                      fit: BoxFit.contain,
                      color: Colors.black,
                      colorBlendMode: BlendMode.srcIn,
                    )
                  : Image.asset(
                      imagePath,
                      width: 80,
                      height: 80,
                      fit: BoxFit.contain,
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}

