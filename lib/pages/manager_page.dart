// lib/pages/management_page.dart

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Define keys for SharedPreferences
const String kUserKey = 'user';
const String kEnlistedPlayersKey = 'enlistedPlayers';

class UsernameSelection {
  String username;
  bool isEnlisted;

  UsernameSelection({required this.username, required this.isEnlisted});
}

class ManagementPage extends StatefulWidget {
  @override
  _ManagementPageState createState() => _ManagementPageState();
}

class _ManagementPageState extends State<ManagementPage> {
  List<UsernameSelection> usernameSelections = [];
  Map<String, bool> initialSelections = {};
  bool isTierMethod = false;
  String? user;
  bool accessDenied = false;

  // List to track the order of selected usernames
  List<String> selectedUsernames = [];

  @override
  void initState() {
    super.initState();
    fetchUserAndData();
  }

  void fetchUserAndData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    user = prefs.getString(kUserKey);

    if (user != 'doron'&& user!='dor') {
      setState(() {
        accessDenied = true;
      });
      return;
    }

    await fetchData(); // Fetch data from server
    await _loadEnlistedPlayers(); // Load enlisted players from SharedPreferences

    // Update usernameSelections based on loaded enlisted players
    setState(() {
      for (var selection in usernameSelections) {
        selection.isEnlisted = selectedUsernames.contains(selection.username);
      }
      // Initialize initialSelections
      initialSelections = {
        for (var selection in usernameSelections)
          selection.username: selection.isEnlisted
      };
    });
  }

  Future<void> _saveEnlistedPlayers(List<String> players) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(kEnlistedPlayersKey, players);
  }

  Future<void> _loadEnlistedPlayers() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> savedPlayers = prefs.getStringList(kEnlistedPlayersKey) ?? [];
    setState(() {
      selectedUsernames = savedPlayers;
    });
  }

  Future<void> fetchData() async {
    try {
      ApiService apiService = ApiService();
      final usernamesResponse = await apiService.get('usernames');

      if (usernamesResponse['success']) {
        List<dynamic> usernamesList = usernamesResponse['usernames'];
        List<String> usernamesData = List<String>.from(usernamesList);

        List<UsernameSelection> selections = usernamesData.map((username) {
          return UsernameSelection(username: username, isEnlisted: false);
        }).toList();

        setState(() {
          usernameSelections = selections;
        });
      } else {
        // Handle error
        print('Failed to fetch usernames');
      }
    } catch (e) {
      print('Error fetching data: $e');
    }
  }

  // Helper function to split the list into chunks of specified size
  List<List<UsernameSelection>> splitList(
      List<UsernameSelection> list, int chunkSize) {
    List<List<UsernameSelection>> chunks = [];
    for (var i = 0; i < list.length; i += chunkSize) {
      chunks.add(
        list.sublist(
          i,
          i + chunkSize > list.length ? list.length : i + chunkSize,
        ),
      );
    }
    return chunks;
  }

  int currentPlayingCount() {
    return selectedUsernames.length;
  }

  Future<void> handleEnlistUsers() async {
    try {
      ApiService apiService = ApiService();

      List<String> usernamesToEnlist = [];
      List<String> usernamesToUnenlist = [];

      // Determine which users to enlist and unenlist based on changes
      usernameSelections.forEach((selection) {
        bool initial = initialSelections[selection.username] ?? false;
        bool current = selection.isEnlisted;
        if (current != initial) {
          if (current) {
            usernamesToEnlist.add(selection.username);
          } else {
            usernamesToUnenlist.add(selection.username);
          }
        }
      });

      // Reorder usernamesToEnlist based on selectedUsernames to preserve selection order
      usernamesToEnlist.sort((a, b) => selectedUsernames.indexOf(a).compareTo(selectedUsernames.indexOf(b)));

      if (usernamesToEnlist.isNotEmpty || usernamesToUnenlist.isNotEmpty) {
        if (usernamesToEnlist.isNotEmpty) {
          await apiService.post('enlist-users', {
            'usernames': usernamesToEnlist,
            'isTierMethod': isTierMethod,
          });
        }

        if (usernamesToUnenlist.isNotEmpty) {
          await apiService.post('delete-enlist', {
            'usernames': usernamesToUnenlist,
            'isTierMethod': isTierMethod,
          });
        }
      } else {
        // If no changes, still call delete-enlist with isTierMethod
        await apiService.post('delete-enlist', {
          'isTierMethod': isTierMethod,
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Users updated successfully!')),
      );

      // Update initialSelections to reflect current state
      setState(() {
        // Update initialSelections to reflect current state
        usernamesToEnlist.forEach((username) {
          initialSelections[username] = true;
        });
        usernamesToUnenlist.forEach((username) {
          initialSelections[username] = false;
        });
        // We do not overwrite selectedUsernames here
      });

      // Save the updated enlisted players to SharedPreferences
      await _saveEnlistedPlayers(selectedUsernames);
    } catch (e) {
      print('Error updating users: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating users')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (accessDenied) {
      return Scaffold(
        body: Center(
          child: Text(
            'Access Denied!',
            style: TextStyle(
              fontSize: 24,
              color: Colors.red,
            ),
          ),
        ),
      );
    }

    return Scaffold(

      body: Container(
        // Background image
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/bb3d.png'), // Ensure the image exists
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.6),
              BlendMode.dstATop,
            ),
          ),
        ),
        width: double.infinity,
        height: double.infinity,
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Use Tier Method Checkbox
                // (Uncomment and implement as needed)
                /*
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Checkbox(
                      value: isTierMethod,
                      onChanged: (bool? value) {
                        setState(() {
                          isTierMethod = value ?? false;
                        });
                      },
                    ),
                    Text('Tier Method'),
                  ],
                ),
                */
                SizedBox(height: 16.0),
                // Display current playing count
                Container(
                  padding: EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Playing now: ${currentPlayingCount()}',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
                SizedBox(height: 16.0),
                // Update Players Button
                ElevatedButton(
                  onPressed: handleEnlistUsers,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.lightGreen, // Button color
                    foregroundColor: Colors.white, // Text color
                    padding:
                    EdgeInsets.symmetric(horizontal: 20.0, vertical: 15.0),
                    textStyle: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text('Update Players'),
                ),
                SizedBox(height: 16.0),
                // List of Users with Customized Checkboxes in Multiple Columns
                Container(
                  constraints: BoxConstraints(
                    maxHeight: 500, // Adjust as needed
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: usernameSelections.isEmpty
                      ? Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:
                      splitList(usernameSelections, 8).map((chunk) {
                        return Padding(
                          padding:
                          EdgeInsets.symmetric(horizontal: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: chunk.map((selection) {
                              // Determine the index of the user in selectedUsernames
                              int selectedIndex = selectedUsernames
                                  .indexOf(selection.username) +
                                  1; // 1-based index
                              bool isBeyondLimit = selectedIndex > 12;

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 4.0, horizontal: 8.0),
                                child: Row(
                                  children: [
                                    // Customized Circular Checkbox
                                    Transform.scale(
                                      scale: 1.2, // Increase the size
                                      child: Checkbox(
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                            BorderRadius.circular(
                                                50)),
                                        value: selection.isEnlisted,
                                        checkColor: Colors.white,
                                        activeColor: (selection.isEnlisted &&
                                            isBeyondLimit)
                                            ? Colors.orange
                                            : Colors.lightGreen,
                                        onChanged: (bool? value) {
                                          setState(() {
                                            selection.isEnlisted =
                                                value ?? false;
                                            if (selection.isEnlisted) {
                                              // Add to selectedUsernames if not already present
                                              if (!selectedUsernames
                                                  .contains(
                                                  selection.username)) {
                                                selectedUsernames
                                                    .add(
                                                    selection.username);
                                              }
                                            } else {
                                              // Remove from selectedUsernames
                                              selectedUsernames
                                                  .remove(
                                                  selection.username);
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    // Username Text
                                    Text(
                                      selection.username,
                                      style: TextStyle(fontSize: 16),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
