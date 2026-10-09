String sexLabel(String species, String sex) => species.toLowerCase() == 'cavy'
    ? (sex == 'M' ? 'Boar' : 'Sow')
    : (sex == 'M' ? 'Buck' : 'Doe');
bool animalIsLocked(String status) => status == 'sold' || status == 'deceased';
