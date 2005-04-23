use ExtUtils::MakeMaker;
WriteMakefile(
              'NAME'		=> 'CAM::Template',
              'VERSION_FROM'	=> 'lib/CAM/Template.pm',
              'PREREQ_PM'	=> {
              },
              'PL_FILES'        => {},
              ($] >= 5.005 ?
               (ABSTRACT_FROM => 'lib/CAM/Template.pm',
                AUTHOR     => 'Clotho Advanced Media <cpan@clotho.com>') : ()),
);
